import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:video_player_example/common/index.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' show parse;

final _logger = LoggerUtil.create(['iptv']);

/// iptv工具类
class IptvUtil {
  IptvUtil._();

  /// 获取远程直播源类型
  static String _getSourceType() {
   /* final iptvSource = IptvSettings.customIptvSource.isNotEmpty ? IptvSettings.customIptvSource : Constants.iptvSource;

    if (iptvSource.endsWith('.m3u')) {
      return 'm3u';
    } else {
      return 'tvbox';
    }*/
    return 'tvbox';
  }

  static Future<String> getCurrentProvinceInfo() async {
    final response = await RequestUtil.get(
        "https://ip.cn/api/index?ip=&type=0");

    if(response!='') {
      // 解析 json
      final document = jsonDecode(response);

      return document["address"].toString();
    }

    return '';
  }

  /// 获取远程直播源
  static Future<String> _fetchSource(String? url) async {
    //final iptvSource = IptvSettings.customIptvSource.isNotEmpty ? IptvSettings.customIptvSource : Constants.iptvSource;

    _logger.debug('获取远程直播源');

    final location = await getCurrentProvinceInfo();
    var reqUrl='http://8.136.199.131/Home/GetIPTVsByLoc?location=' + location;
    if(url!=null)
      reqUrl+="&ip="+url;
    final result = await RequestUtil.get(reqUrl);
    return result;
  }

  /// 获取缓存直播源文件
  static Future<File> _getCacheFile() async {
    return File('${(await getTemporaryDirectory()).path}/iptv.txt');
  }

  /// 获取缓存直播源
  static Future<String> _getCache() async {
    try {
      final cacheFile = await _getCacheFile();
      if (await cacheFile.exists()) {
        return await cacheFile.readAsString();
      }

      return '';
    } catch (e, st) {
      _logger.handle(e, st);
      return '';
    }
  }

  /*static Future  _loadAsset() async{
    var jsonStr = await rootBundle.loadString('assets/json/iptvsource.json');
    var list = json.decode(jsonStr);
    return list;
  }*/
  /// 解析直播源m3u
  static Future<List<IptvGroup>> _parseSourceM3u(String source) async {
    var groupList = <IptvGroup>[];

    final lines = source.split('\n');

    var channel = 0;
    for (final (lineIdx, line) in lines.indexed) {
      if (line.isEmpty || !line.startsWith('#EXTINF:')) {
        continue;
      }

      final groupName = RegExp('group-title="(.*?)"').firstMatch(line)?.group(1) ?? '其他';
      final name = line.split(',')[1];

      if (IptvSettings.iptvSourceSimplify) {
        if (!name.toLowerCase().startsWith('cctv') && !name.endsWith('卫视')) continue;
      }

      final group = groupList.firstWhere((it) => it.name == groupName, orElse: () {
        final group = IptvGroup(idx: groupList.length, name: groupName, list: []);
        groupList.add(group);
        return group;
      });

      final iptv = Iptv(
        idx: group.list.length,
        channel: ++channel,
        groupIdx: group.idx,
        name: name,
        url: lines[lineIdx + 1],
        tvgName: RegExp('tvg-name="(.*?)"').firstMatch(line)?.group(1) ?? name,
      );

      group.list.add(iptv);
    }

    _logger.debug('解析m3u完成: ${groupList.length}个分组, $channel个频道');

    return groupList;
  }


  /// 解析直播源tvbox
  static Future<List<IptvGroup>> _parseSourceTvbox(String source) async {
    var groupList = <IptvGroup>[];


    final lines = jsonDecode(source);

    var channel = 0;
    for (var i = 0; i < lines.length; i++) {
      final groupName = lines[i]['grouptitle'].toString().trim();
      final name = lines[i]["title"].toString().trim();

      final group = groupList.firstWhere((it) => it.name == groupName,
          orElse: () {
            final group = IptvGroup(
                idx: groupList.length, name: groupName, list: []);
            groupList.add(group);
            return group;
          });

      final iptv = Iptv(
        idx: group.list.length,
        channel: ++channel,
        groupIdx: group.idx,
        name: name,
        url: lines[i]['url'].toString().trim(),
        tvgName: name,
      );

      group.list.add(iptv);
    }


    _logger.debug('解析tvbox完成: ${groupList.length}个分组, $channel个频道');

    return groupList;
  }

  /// 解析直播源
  static Future<List<IptvGroup>> _parseSource(String source) {
    if (_getSourceType() == 'm3u') {
      return _parseSourceM3u(source);
    } else {
      return _parseSourceTvbox(source);
    }
  }

  /// 刷新并获取直播源
  static Future<List<IptvGroup>> refreshAndGet() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    if (now - IptvSettings.iptvSourceCacheTime < 1 * 60 * 60 * 1000) {
      final cache = await _getCache();

      if (cache.isNotEmpty) {
        _logger.debug('使用缓存直播源');
        return _parseSource(cache);
      }
    }

    final source = await _fetchSource(null);

    /*final cacheFile = await _getCacheFile();
    await cacheFile.writeAsString(source);
    IptvSettings.iptvSourceCacheTime = now;*/

    return _parseSource(source);
  }

  //更新IPTV
  static Future<List<IptvGroup>> updateIPTV(String url) async {

    final source = await _fetchSource(url);

    return _parseSource(source);
  }
}
