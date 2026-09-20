import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:video_player_example/common/utils/iptv_parser.dart';

const jsonBuiltin = '''[{"grouptitle":"央视频道","title":"CCTV1","url":"http://a/1.m3u8"},{"grouptitle":"卫视频道","title":"湖南卫视","url":"http://b/2.m3u8"}]''';

const m3uSource = '''#EXTM3U x-tvg-url="http://epg.xml"catchup="append"
#EXTINF:-1 tvg-name="CCTV1" tvg-logo="http://l/1.png" group-title="央视频道",CCTV-1
http://a/1.m3u8
#EXTINF:-1 tvg-name="CCTV2" tvg-logo="http://l/2.png" group-title="央视频道",CCTV-2
http://a/2.m3u8
#EXTINF:-1 tvg-name="湖南卫视" tvg-logo="http://l/3.png" group-title="卫视频道",湖南卫视
http://b/3.m3u8''';

const tvboxSource = '''央视频道,#genre#
CCTV1,http://a/1.m3u8
CCTV2，http://a/2.m3u8''';

void main() {
  group('detectSourceFormat', () {
    test('JSON 数组识别为 inline', () {
      expect(detectSourceFormat(jsonBuiltin), IptvSourceFormat.inline);
    });

    test('#EXTM3U 开头识别为 m3u', () {
      expect(detectSourceFormat(m3uSource), IptvSourceFormat.m3u);
    });

    test('tvbox 文本识别为 tvbox', () {
      expect(detectSourceFormat(tvboxSource), IptvSourceFormat.tvbox);
    });

    test('前导空白不影响 m3u 识别', () {
      expect(detectSourceFormat('\n  #EXTM3U x-tvg-url="..."'), IptvSourceFormat.m3u);
    });
  });

  group('parseIptvSource', () {
    test('内置 JSON 源按内容解析为 inline 分组（不依赖自定义源配置）', () async {
      final groups = await parseIptvSource(jsonBuiltin);
      expect(groups.length, 2);
      expect(groups.map((g) => g.name).toList(), ['央视频道', '卫视频道']);
      expect(groups.first.list.first.name, 'CCTV1');
      expect(groups.first.list.first.url, 'http://a/1.m3u8');
    });

    test('m3u 源解析分组/频道名/URL/tvgName', () async {
      final groups = await parseIptvSource(m3uSource);
      expect(groups.length, 2);

      final cctv = groups.firstWhere((g) => g.name == '央视频道');
      expect(cctv.list.length, 2);
      expect(cctv.list[0].name, 'CCTV-1');
      expect(cctv.list[0].url, 'http://a/1.m3u8');
      expect(cctv.list[0].tvgName, 'CCTV1');

      final weishi = groups.firstWhere((g) => g.name == '卫视频道');
      expect(weishi.list.single.name, '湖南卫视');
      expect(weishi.list.single.url, 'http://b/3.m3u8');
    });

    test('tvbox 源解析', () async {
      final groups = await parseIptvSource(tvboxSource);
      expect(groups.length, 1);
      expect(groups.single.name, '央视频道');
      expect(groups.single.list.length, 2);
      expect(groups.single.list[0].name, 'CCTV1');
      expect(groups.single.list[0].url, 'http://a/1.m3u8');
      expect(groups.single.list[1].name, 'CCTV2');
      expect(groups.single.list[1].url, 'http://a/2.m3u8');
    });
  });

  // 这条回归用的夹具里含真实直播源地址，按红线不进 Git（见 .gitignore），
  // 所以只在本地存在时才跑 —— clone 下来的干净仓库会跳过，不会误报失败。
  group('result.m3u 回归', () {
    test('wget.la 代理的 result.m3u 完整解析', () async {
      final fixture = File('test/fixtures/result.m3u');
      if (!fixture.existsSync()) {
        _log('跳过：本地缺少夹具 test/fixtures/result.m3u');
        return;
      }
      final source = fixture.readAsStringSync();
      final groups = await parseIptvSource(source);
      final total = groups.fold<int>(0, (sum, g) => sum + g.list.length);
      expect(groups.length, 9);
      expect(total, 119);
      expect(groups.first.name, '🕘️更新时间');
      expect(groups.first.list.single.name, '2026-02-03 19:05:43');
      final cctv = groups.firstWhere((g) => g.name == '央视频道');
      expect(cctv.list.first.name, 'CCTV-1');
      expect(cctv.list.first.url, 'http://ott.example.com/TVOD/88888888/224/3221225829/1.m3u8?servicetype=1');
    });
  });
}

void _log(String message) {
  // ignore: avoid_print
  print('[iptv_parser] $message');
}
