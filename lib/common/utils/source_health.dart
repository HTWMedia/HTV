import 'dart:async';

import 'logger.dart';
import 'prefs.dart';

final _logger = LoggerUtil.create(['源健康度']);

/// 直播源健康度记忆
///
/// 解决什么问题：切源原来是 `(i + 1) % n` 盲轮转，一个频道的源里前几条是死的话，
/// 每次进这个台都要重踩一遍起播看门狗（默认 12s），而且**第二次打开 App 不会比
/// 第一次快** —— 失败经验一点没留下。有了记忆之后，坏源直接排在后面。
///
/// 为什么放在客户端而不是让后端下发质量分：
/// HTV 的源是按「省份 × 运营商」分发的（31 省 × 3 运营商），而后端做连通性测试
/// 时用的是**服务器自己那张网**，跟「湖北移动宽带用户」的实际网络并不是一回事
/// （IPTVUpdateService 的注释也写了 rtp 组播源「跨设备跨网都不可用」）。
/// 服务端打分解决不了跨网差异，只有用户本机的真实播放结果才准。
/// 顺带也就不必改后端频道列表格式 —— 对已在线的大量老客户端零影响。
///
/// 存储取舍：**只记坏源，不记好源**。默认所有源都是健康的，只有失败过的才入库，
/// 这样数据量极小（用户实际看过的频道里坏源通常几十条），一个 StringList 装得下。
class SourceHealthUtil {
  SourceHealthUtil._();

  /// 本地存储键（公开是便于测试构造数据与线上排查）
  static const String prefsKey = 'iptv_source_health';

  /// 连续失败 N 次后要冷却多久（分钟），下标 = 失败次数 - 1
  ///
  /// 源可能只是临时抽风（源站并发高、网络抖动），永久拉黑等于自己砍源，
  /// 所以冷却期一过就再给一次机会；再失败就把冷却再拉长一档。
  /// 10min → 1h → 6h → 12h → 24h（封顶）
  static const List<int> _cooldownMinutes = [10, 60, 360, 720, 1440];

  /// 冷却期过后仍未再失败，多久就彻底忘掉这条记录
  ///
  /// 源列表会随后端更新整体变化，不清理的话旧源的记录会一直堆积。
  static const int _forgetAfterMs = 7 * 24 * 60 * 60 * 1000;

  /// 最多保留多少条记录，超出后按最后失败时间从旧到新淘汰
  static const int _maxEntries = 2000;

  /// url → 健康记录
  static final Map<String, _Health> _records = {};

  static bool _loaded = false;

  /// 健康度记录是否已从本地载入
  static bool get isLoaded => _loaded;

  /// 当前记录条数（测试与自检用）
  static int get recordCount => _records.length;

  /// 从本地存储载入健康度记录
  ///
  /// 在 `main()` 里 `PrefsUtil.init()` 之后调用一次即可。
  /// [rank] 是同步的，载入完成前一律返回 0 —— 行为退化成改动前的盲轮转，
  /// 不会比现状更差，所以这里失败也不必中断启动。
  static Future<void> load() async {
    if (_loaded) return;

    try {
      final list = PrefsUtil.getStringList(prefsKey);
      _records.clear();
      if (list != null) {
        for (final item in list) {
          final h = _Health.decode(item);
          if (h != null) _records[h.url] = h;
        }
      }
      _prune();
      _logger.debug('载入源健康度记录 ${_records.length} 条');
    } catch (e) {
      // 读不到就按"没有记录"处理。健康度只是加速起播的优化，
      // 绝不能因为读盘失败挡住 App 启动。
      _records.clear();
      _logger.warning('载入源健康度失败，按无记录处理: $e');
    } finally {
      // 无论成败都标记已尝试：避免启动路径上重复读盘
      _loaded = true;
    }
  }

  /// 该源的排序权重：0 表示可以优先尝试，越大越靠后
  static int rank(String url) {
    final h = _records[url];
    if (h == null) return 0;

    final now = DateTime.now().millisecondsSinceEpoch;
    // 冷却期已过：再给一次机会，而不是一直压着
    if (now - h.lastFailMs >= _cooldownMsFor(h.failCount)) return 0;

    return 1 + h.failCount;
  }

  /// 按健康度**稳定**排序后的源列表
  ///
  /// 稳定很关键：权重相同时必须保持后端下发的原始顺序，否则每次进频道都会重排，
  /// 用户手动切源时的位置感会乱，也会让"源 X/Y"的显示对不上。
  static List<String> ordered(List<String> sources) {
    if (sources.length <= 1) return sources;

    final indexed = sources.asMap().entries.toList()
      ..sort((a, b) {
        final ra = rank(a.value);
        final rb = rank(b.value);
        if (ra != rb) return ra.compareTo(rb);
        return a.key.compareTo(b.key);
      });

    return indexed.map((e) => e.value).toList();
  }

  /// 拆分 `Iptv.url` 字段（多源用 `;` 连接）
  static List<String> splitSources(String urlField) {
    return urlField
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// 该频道最应该先试的那条源
  ///
  /// 未载入或无记录时就是后端顺序的第一条，即改动前的行为。
  static String pickBest(String urlField) {
    final sources = splitSources(urlField);
    if (sources.isEmpty) return urlField.trim();
    return ordered(sources).first;
  }

  /// 播放成功：把这条源的失败记录抹掉
  ///
  /// 包含两种情况：正常起播，以及冷却期过后重试成功（这时源其实已经恢复）。
  /// 本来就没有记录的源不做任何事，也不触发落盘。
  static void recordSuccess(String url) {
    if (url.isEmpty) return;
    if (_records.remove(url) == null) return;
    _logger.debug('源恢复，清除失败记录: $url');
    _scheduleSave();
  }

  /// 播放失败：记一次，并把冷却期按失败次数拉长一档
  static void recordFailure(String url) {
    if (url.isEmpty) return;

    final old = _records[url];
    _records[url] = _Health(
      url: url,
      failCount: (old?.failCount ?? 0) + 1,
      lastFailMs: DateTime.now().millisecondsSinceEpoch,
    );
    _logger.debug('源失败 ${_records[url]!.failCount} 次: $url');
    _scheduleSave();
  }

  static Timer? _saveTimer;

  /// 落盘去抖
  ///
  /// 换台、切源都会触发记录，每次都同步写 SharedPreferences 太频繁，
  /// 攒 2 秒写一次足够 —— 即使进程被杀，丢的也只是最后两秒的经验。
  static void _scheduleSave() {
    // 还没载入过就说明本地存储没就绪（未初始化，或读取时抛过异常）。
    // 这时不排定时器：一来避免把已有记录覆盖成空，二来不会在
    // 未初始化 Prefs 的场景（如只测播放器的用例）里留下悬空 Timer 去炸异步错误。
    if (!_loaded) return;

    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      _saveTimer = null;
      saveNow();
    });
  }

  /// 立即落盘（退出前或测试里调用）
  static Future<void> saveNow() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (!_loaded) return;

    try {
      _prune();
      await PrefsUtil.setStringList(
          prefsKey, _records.values.map((h) => h.encode()).toList());
    } catch (e) {
      // 落盘失败无所谓：内存里的记录本轮照样生效，下次启动再积累
      _logger.warning('保存源健康度失败: $e');
    }
  }

  /// 清掉过期与超额的记录
  static void _prune() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _records.removeWhere((_, h) => now - h.lastFailMs > _forgetAfterMs);

    if (_records.length <= _maxEntries) return;

    // 新的在前，淘汰尾巴上最旧的
    final sorted = _records.values.toList()
      ..sort((a, b) => b.lastFailMs.compareTo(a.lastFailMs));
    for (final h in sorted.skip(_maxEntries)) {
      _records.remove(h.url);
    }
  }

  /// 仅测试使用：清空内存与载入标记
  static void resetForTest() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _records.clear();
    _loaded = false;
  }

  static int _cooldownMsFor(int failCount) {
    var i = failCount - 1;
    if (i < 0) i = 0;
    if (i >= _cooldownMinutes.length) i = _cooldownMinutes.length - 1;
    return _cooldownMinutes[i] * 60 * 1000;
  }
}

/// 单条源的健康记录
///
/// 编码为 `失败次数|最后失败时刻|url`，两个数字放前面、url 放最后：
/// url 里理论上可能出现 `|`，按前两个分隔符切就不会被 url 内容干扰。
class _Health {
  const _Health({
    required this.url,
    required this.failCount,
    required this.lastFailMs,
  });

  final String url;
  final int failCount;
  final int lastFailMs;

  String encode() => '$failCount|$lastFailMs|$url';

  static _Health? decode(String s) {
    final i1 = s.indexOf('|');
    if (i1 < 0) return null;
    final i2 = s.indexOf('|', i1 + 1);
    if (i2 < 0) return null;

    final fail = int.tryParse(s.substring(0, i1));
    final lastFail = int.tryParse(s.substring(i1 + 1, i2));
    final url = s.substring(i2 + 1);
    if (fail == null || lastFail == null || url.isEmpty) return null;

    return _Health(url: url, failCount: fail, lastFailMs: lastFail);
  }
}
