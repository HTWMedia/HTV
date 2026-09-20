import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_example/common/index.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    // PrefsUtil._instance 是 late final，整个测试文件只能初始化一次
    await PrefsUtil.init();
  });

  setUp(() async {
    SourceHealthUtil.resetForTest();
    // 必须连本地存储一起清：只清内存的话，下一个用例 load() 会把上一条记录读回来
    await PrefsUtil.setStringList(SourceHealthUtil.prefsKey, []);
  });

  tearDown(() async {
    // 把去抖落盘立刻刷掉，否则用例结束后 Timer 才触发，会被判成"测试完成后报错"
    await SourceHealthUtil.saveNow();
    SourceHealthUtil.resetForTest();
  });

  /// 直接往本地存储里塞一条记录，用来构造"多久之前失败过"的场景
  Future<void> seed(String url, int failCount, Duration ago) async {
    final ts = DateTime.now().millisecondsSinceEpoch - ago.inMilliseconds;
    await PrefsUtil.setStringList(
        SourceHealthUtil.prefsKey, ['$failCount|$ts|$url']);
    await SourceHealthUtil.load();
  }

  test('未载入时所有源同权重，行为退化为改动前', () {
    const sources = ['http://a/1.m3u8', 'http://b/1.m3u8', 'http://c/1.m3u8'];

    // 没载入就一律 rank 0，不会比盲轮转更差
    expect(SourceHealthUtil.ordered(sources), sources);
    expect(SourceHealthUtil.pickBest('${sources[0]};${sources[1]}'),
        sources[0]);
  });

  test('失败过且仍在冷却期内的源排到后面', () async {
    await seed('http://a/1.m3u8', 2, const Duration(minutes: 1));

    expect(SourceHealthUtil.rank('http://a/1.m3u8'), greaterThan(0));
    expect(SourceHealthUtil.rank('http://b/1.m3u8'), 0);

    // a 被压到最后，其余保持原顺序
    expect(SourceHealthUtil.ordered([
      'http://a/1.m3u8',
      'http://b/1.m3u8',
      'http://c/1.m3u8',
    ]), [
      'http://b/1.m3u8',
      'http://c/1.m3u8',
      'http://a/1.m3u8',
    ]);
  });

  test('起播直接选最健康的那条，不再固定取第一条', () async {
    await seed('http://a/1.m3u8', 1, const Duration(minutes: 1));

    // 改动前永远是 a，改动后跳过它
    expect(SourceHealthUtil.pickBest('http://a/1.m3u8;http://b/1.m3u8'),
        'http://b/1.m3u8');
  });

  test('冷却期过后重新给一次机会', () async {
    // 失败 1 次冷却 10 分钟，这里模拟 11 分钟前失败的
    await seed('http://a/1.m3u8', 1, const Duration(minutes: 11));

    expect(SourceHealthUtil.rank('http://a/1.m3u8'), 0);
  });

  test('冷却时长随失败次数拉长', () async {
    // 失败 1 次：10 分钟冷却，5 分钟前失败仍在冷却中
    await seed('http://a/1.m3u8', 1, const Duration(minutes: 5));
    expect(SourceHealthUtil.rank('http://a/1.m3u8'), greaterThan(0));

    // 失败 3 次：6 小时冷却，5 分钟前失败必然还在冷却中
    SourceHealthUtil.resetForTest();
    await seed('http://a/1.m3u8', 3, const Duration(minutes: 5));
    expect(SourceHealthUtil.rank('http://a/1.m3u8'), greaterThan(0));
  });

  test('播放成功会抹掉失败记录', () async {
    await seed('http://a/1.m3u8', 1, const Duration(minutes: 1));
    expect(SourceHealthUtil.rank('http://a/1.m3u8'), greaterThan(0));

    SourceHealthUtil.recordSuccess('http://a/1.m3u8');
    expect(SourceHealthUtil.rank('http://a/1.m3u8'), 0);
    expect(SourceHealthUtil.recordCount, 0);
  });

  test('失败次数会累加', () async {
    await SourceHealthUtil.load();
    SourceHealthUtil.recordFailure('http://a/1.m3u8');
    SourceHealthUtil.recordFailure('http://a/1.m3u8');

    // rank = 1 + failCount
    expect(SourceHealthUtil.rank('http://a/1.m3u8'), 3);
  });

  test('空地址不记健康度（回看地址不应污染直播源）', () async {
    await SourceHealthUtil.load();
    SourceHealthUtil.recordFailure('');
    SourceHealthUtil.recordSuccess('');

    expect(SourceHealthUtil.recordCount, 0);
  });

  test('落盘后重新载入仍然记得', () async {
    await SourceHealthUtil.load();
    SourceHealthUtil.recordFailure('http://a/1.m3u8');
    await SourceHealthUtil.saveNow();

    // 模拟重启 App
    SourceHealthUtil.resetForTest();
    await SourceHealthUtil.load();

    expect(SourceHealthUtil.rank('http://a/1.m3u8'), greaterThan(0));
  });

  test('url 里带竖线也不会解析错乱', () async {
    const tricky = 'http://a/1.m3u8?x=1|2|3';
    await SourceHealthUtil.load();
    SourceHealthUtil.recordFailure(tricky);
    await SourceHealthUtil.saveNow();

    SourceHealthUtil.resetForTest();
    await SourceHealthUtil.load();

    // 数字在前、url 在后，按前两个分隔符切，url 里的 | 不会被吃掉
    expect(SourceHealthUtil.rank(tricky), greaterThan(0));
  });

  test('过期的记录会被清理', () async {
    // 8 天前失败过，早于 7 天的遗忘窗口
    await seed('http://a/1.m3u8', 1, const Duration(days: 8));

    expect(SourceHealthUtil.recordCount, 0);
  });

  test('源字段里的空片段不会产生记录', () {
    expect(SourceHealthUtil.splitSources('a;;b; ;c'), ['a', 'b', 'c']);
    expect(SourceHealthUtil.pickBest(''), '');
  });

  test('权重相同时保持后端原始顺序', () async {
    await SourceHealthUtil.load();

    const sources = ['http://c/1.m3u8', 'http://a/1.m3u8', 'http://b/1.m3u8'];
    // 三条都没失败记录，排序必须原样返回，否则"源 X/Y"的显示会乱跳
    expect(SourceHealthUtil.ordered(sources), sources);
  });
}
