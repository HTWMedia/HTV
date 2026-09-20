import 'package:intl/intl.dart';

import '../enums/iptv_setting.dart';
import '../models/epg.dart';
import '../models/iptv.dart';

/// 回看（catch-up）工具
///
/// m3u 里用 `catchup` / `catchup-source` 声明回看能力，例如：
/// ```
/// #EXTM3U catchup="append" catchup-source="?playseek=${(b)yyyyMMddHHmmss}-${(e)yyyyMMddHHmmss}"
/// ```
/// `${(b)…}` 是节目开始时间、`${(e)…}` 是结束时间。
/// 有了 EPG 里已播出节目的 start/stop，就能拼出那段录像的点播地址。
///
/// 这套占位符写法来自 m3u 的 catchup 扩展：
/// - `catchup="append"`：把模板**追加**到直播地址后面
/// - `catchup="default" / "shift" / "vod"`：模板本身就是完整地址
class CatchupUtil {
  CatchupUtil._();

  /// ${(b)yyyyMMddHHmmss} / ${(e)yyyyMMddHHmmss} 形式的占位符
  static final RegExp _placeholders = RegExp(r'\$\{\(([be])\)([^}]*)\}');

  static final RegExp _catchupAttr = RegExp(r'\bcatchup="([^"]*)"');
  static final RegExp _catchupSourceAttr = RegExp(r'\bcatchup-source="([^"]*)"');
  static final RegExp _catchupDaysAttr = RegExp(r'\bcatchup-days="([^"]*)"');

  /// 读取回看声明
  ///
  /// [extinfLine] 是频道自己的 `#EXTINF` 行，[head] 是 `#EXTM3U` 全局头。
  /// 频道级属性优先，没有才回退到全局。
  static ({String type, String source, int days}) resolve(String head, String extinfLine) {
    String pick(RegExp re, String fallback) {
      return re.firstMatch(extinfLine)?.group(1) ??
          re.firstMatch(head)?.group(1) ??
          fallback;
    }

    return (
      type: pick(_catchupAttr, ''),
      source: pick(_catchupSourceAttr, ''),
      days: int.tryParse(pick(_catchupDaysAttr, '1')) ?? 1,
    );
  }

  /// 把 [startMs] / [stopMs] 代入模板，替换 ${(b)…} 与 ${(e)…}
  static String fillTemplate(
    String template, {
    required int startMs,
    required int stopMs,
  }) {
    return template.replaceAllMapped(_placeholders, (m) {
      final pattern = m.group(2)!;
      final millis = m.group(1) == 'b' ? startMs : stopMs;
      final utc = DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
      // EPG 的 start/stop 是带时区的绝对时刻，这里按偏移量还原成服务端要的字面时间
      final target = utc.add(Duration(hours: IptvSettings.catchupUtcOffsetHours));
      try {
        return DateFormat(pattern).format(target);
      } catch (_) {
        // 模板用了不认识的 Java pattern，退回最常见的写法
        return DateFormat('yyyyMMddHHmmss').format(target);
      }
    });
  }

  /// 生成某段节目的回看地址
  ///
  /// 返回候选列表（通常 1~2 个）：`append` 模式下，直播地址是否带尾斜杠
  /// 服务端要求可能不同，两种都试一遍最稳。
  static List<String> buildUrls(
    Iptv iptv, {
    required int startMs,
    required int stopMs,
  }) {
    if (!iptv.supportCatchup) return const [];

    final filled = fillTemplate(iptv.catchupSource, startMs: startMs, stopMs: stopMs);

    // 模板本身已经是完整地址
    if (iptv.catchup != 'append') return [filled];

    final base = iptv.url.split(';').first.trim();
    if (base.isEmpty) return [filled];

    final urls = <String>{};
    urls.add(base + filled);
    if (base.endsWith('/')) {
      urls.add(base.substring(0, base.length - 1) + filled);
    }
    return urls.toList();
  }

  /// 挑一个适合做回看探测的往期节目
  ///
  /// 条件：已经完整播出、时长不短于 [minDuration]、且离现在最近。
  /// 刚开播几分钟的节目不适合 —— 服务端往往还没切出完整录像。
  static EpgProgramme? pickProbeProgramme(
    List<EpgProgramme> programmes, {
    Duration minDuration = const Duration(minutes: 5),
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;

    EpgProgramme? best;
    for (final p in programmes) {
      if (p.stop > now) continue; // 还没播完，跳过
      if (p.stop - p.start < minDuration.inMilliseconds) continue;
      if (best == null || p.stop > best.stop) best = p;
    }
    return best;
  }
}
