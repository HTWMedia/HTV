import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_example/common/index.dart';

/// 壳源分离的行为约定：App 自带的只是「一个可替换的服务地址」，不是源数据。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await PrefsUtil.init();
  });

  group('默认源服务地址', () {
    test('未配置时取内置默认值，保持开箱即用', () {
      expect(IptvSettings.defaultIptvSourceApi, Constants.defaultIptvSourceApi);
    });

    test('置空表示停用内置源（只加载自定义源）', () async {
      IptvSettings.defaultIptvSourceApi = '';
      expect(IptvSettings.defaultIptvSourceApi, isEmpty);
    });

    test('改成第三方接口后读回新值', () async {
      IptvSettings.defaultIptvSourceApi = 'https://example.com/api/iptv';
      expect(IptvSettings.defaultIptvSourceApi, 'https://example.com/api/iptv');
    });

    test('改地址必须让内置源缓存失效，否则会拿旧地址的缓存继续用', () async {
      IptvSettings.iptvSourceCacheTime =
          DateTime.now().millisecondsSinceEpoch;
      expect(IptvSettings.iptvSourceCacheTime, greaterThan(0));

      IptvSettings.defaultIptvSourceApi = 'https://example.com/api/iptv';
      expect(IptvSettings.iptvSourceCacheTime, 0);
    });
  });
}
