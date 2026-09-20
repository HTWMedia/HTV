import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_example/common/index.dart';

const _customUrl = 'http://custom.test/result.m3u';

const _jsonBuiltin = '''[{"grouptitle":"央视频道","title":"CCTV1","url":"http://a/1.m3u8"},{"grouptitle":"央视频道","title":"CCTV2","url":"http://a/2.m3u8"}]''';

const _m3uCustom = '''#EXTM3U
#EXTINF:-1 tvg-name="CCTV1" group-title="自定义组",CCTV1
http://c/1.m3u8
#EXTINF:-1 tvg-name="凤凰卫视" group-title="自定义组",凤凰卫视
http://c/2.m3u8''';

/// 中间分组「购物频道」在精简过滤下会被整组丢弃，用于复现 groupIdx 错位
const _jsonSimplify = '''[
{"grouptitle":"央视频道","title":"CCTV1","url":"http://a/1.m3u8"},
{"grouptitle":"央视频道","title":"CCTV2","url":"http://a/2.m3u8"},
{"grouptitle":"购物频道","title":"优购物","url":"http://a/3.m3u8"},
{"grouptitle":"购物频道","title":"快乐购","url":"http://a/4.m3u8"},
{"grouptitle":"地方频道","title":"湖南卫视","url":"http://a/5.m3u8"}
]''';

/// 自定义组频道与内置源完全同名，去重后整组被丢弃
const _m3uDuplicate = '''#EXTM3U
#EXTINF:-1 tvg-name="CCTV1" group-title="重复组",CCTV1
http://c/1.m3u8''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefsUtil.init();

    tmpDir = Directory.systemTemp.createTempSync('iptv_cache_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getTemporaryDirectory') return tmpDir.path;
        return null;
      },
    );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    tmpDir.deleteSync(recursive: true);
  });

  setUp(() {
    for (final f in ['iptv.txt', 'custom.txt']) {
      final file = File('${tmpDir.path}/$f');
      if (file.existsSync()) file.deleteSync();
    }
  });

  group('isCustomSourceCacheStale', () {
    test('缓存新鲜且地址匹配时未失效', () {
      IptvSettings.customIptvSource = _customUrl;
      IptvSettings.customIptvSourceCacheTime = DateTime.now().millisecondsSinceEpoch;
      IptvSettings.customIptvSourceCacheUrl = _customUrl;

      expect(IptvUtil.isCustomSourceCacheStale(), isFalse);
    });

    test('超过缓存保持时间后失效', () {
      IptvSettings.customIptvSource = _customUrl;
      IptvSettings.customIptvSourceCacheTime =
          DateTime.now().millisecondsSinceEpoch - IptvSettings.iptvSourceCacheKeepTime - 1000;
      IptvSettings.customIptvSourceCacheUrl = _customUrl;

      expect(IptvUtil.isCustomSourceCacheStale(), isTrue);
    });

    test('自定义源地址变更后失效', () {
      IptvSettings.customIptvSource = 'http://custom.test/new.m3u';
      IptvSettings.customIptvSourceCacheTime = DateTime.now().millisecondsSinceEpoch;
      IptvSettings.customIptvSourceCacheUrl = _customUrl;

      expect(IptvUtil.isCustomSourceCacheStale(), isTrue);
    });
  });

  group('buildMergedGroups', () {
    test('内置 JSON 与自定义 m3u 合并：分组加(自定义)后缀、同名频道去重合并URL、全局重排频道号', () async {
      final groups = await IptvUtil.buildMergedGroups(_jsonBuiltin, _m3uCustom);

      expect(groups.length, 2);
      expect(groups[0].name, '央视频道');
      expect(groups[0].list.length, 2);
      expect(groups[0].list[0].name, 'CCTV1');
      expect(groups[0].list[0].url, 'http://a/1.m3u8;http://c/1.m3u8');
      expect(groups[1].name, '自定义组(自定义)');
      expect(groups[1].list.single.name, '凤凰卫视');
      expect(groups[1].list.single.channel, 3);
    });

    test('无内置源时仅返回自定义分组', () async {
      final groups = await IptvUtil.buildMergedGroups('', _m3uCustom);

      expect(groups.length, 1);
      expect(groups.single.name, '自定义组(自定义)');
      expect(groups.single.list.length, 2);
    });

    test('内置源与自定义源均为空时返回空列表', () async {
      final groups = await IptvUtil.buildMergedGroups('', '');

      expect(groups, isEmpty);
    });

    group('分组索引连续性', () {
      /// idx / groupIdx 被频道面板当作位置索引使用，一旦出现空洞会越界崩溃
      void expectIndexesMatchPosition(List<IptvGroup> groups) {
        var channel = 0;
        for (var g = 0; g < groups.length; g++) {
          final group = groups[g];
          expect(group.idx, g, reason: '分组 idx 必须等于实际下标');
          for (var i = 0; i < group.list.length; i++) {
            final iptv = group.list[i];
            expect(iptv.groupIdx, g, reason: 'groupIdx 必须等于分组下标');
            expect(iptv.idx, i, reason: 'idx 必须等于组内下标');
            expect(iptv.channel, ++channel, reason: '频道号需全局连号');
          }
        }
      }

      test('精简过滤丢弃分组后序号重排', () async {
        final simplifyBefore = IptvSettings.iptvSourceSimplify;
        addTearDown(() => IptvSettings.iptvSourceSimplify = simplifyBefore);
        IptvSettings.iptvSourceSimplify = true;
        IptvSettings.allowedChannels = [];

        final groups = await IptvUtil.buildMergedGroups(_jsonSimplify, '');

        expect(groups.length, 2, reason: '「购物频道」应被整组丢弃');
        expect(groups.map((g) => g.name), ['央视频道', '地方频道']);
        expectIndexesMatchPosition(groups);
      });

      test('同名去重丢弃整个自定义分组后序号重排', () async {
        final groups = await IptvUtil.buildMergedGroups(_jsonBuiltin, _m3uDuplicate);

        expect(groups.length, 1, reason: '「重复组」应被整组丢弃');
        expect(groups.single.name, '央视频道');
        expectIndexesMatchPosition(groups);
      });
    });
  });

  group('getCachedGroups', () {
    test('无任何缓存时返回 null', () async {
      IptvSettings.customIptvSource = '';
      expect(await IptvUtil.getCachedGroups(), isNull);
    });

    test('内置+自定义缓存存在且地址匹配时合并返回', () async {
      File('${tmpDir.path}/iptv.txt').writeAsStringSync(_jsonBuiltin);
      File('${tmpDir.path}/custom.txt').writeAsStringSync(_m3uCustom);
      IptvSettings.customIptvSource = _customUrl;
      IptvSettings.customIptvSourceCacheTime = DateTime.now().millisecondsSinceEpoch;
      IptvSettings.customIptvSourceCacheUrl = _customUrl;

      final groups = await IptvUtil.getCachedGroups();

      expect(groups, isNotNull);
      expect(groups!.length, 2);
      expect(groups.any((g) => g.name == '自定义组(自定义)'), isTrue);
      expect(groups.first.list.first.url, 'http://a/1.m3u8;http://c/1.m3u8');
    });

    test('自定义缓存地址与当前配置不匹配时忽略自定义缓存', () async {
      File('${tmpDir.path}/iptv.txt').writeAsStringSync(_jsonBuiltin);
      File('${tmpDir.path}/custom.txt').writeAsStringSync(_m3uCustom);
      IptvSettings.customIptvSource = 'http://custom.test/new.m3u';
      IptvSettings.customIptvSourceCacheTime = DateTime.now().millisecondsSinceEpoch;
      IptvSettings.customIptvSourceCacheUrl = _customUrl;

      final groups = await IptvUtil.getCachedGroups();

      expect(groups, isNotNull);
      expect(groups!.length, 1);
      expect(groups.single.name, '央视频道');
    });
  });
}
