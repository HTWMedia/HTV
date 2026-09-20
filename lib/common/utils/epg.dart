import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:video_player_example/common/index.dart';
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';

final _logger = LoggerUtil.create(['epg']);

/// 节目单工具
class EpgUtil {
  EpgUtil._();

  /// 获取远程epg xml
  static Future<String> _fetchXml() async {
    _logger.debug('获取远程xml: ${Constants.iptvEpgXml}');
    final result = await RequestUtil.get(Constants.iptvEpgXml);
    return result;
  }

  /// 获取缓存epg xml文件
  static Future<File> _getCacheXmlFile() async {
    return File('${(await getTemporaryDirectory()).path}/epg.xml');
  }

  /// 获取缓存epg xml
  static Future<String?> _getCacheXml() async {
    try {
      final cacheFile = await _getCacheXmlFile();
      if (await cacheFile.exists()) {
        return await cacheFile.readAsString();
      }

      return null;
    } catch (e, st) {
      _logger.handle(e, st);
      return null;
    }
  }

  /// 刷新并获取epg xml
  static Future<String> _refreshAndGetXml() async {
    final now = DateTime.now();
    final cacheAt = DateTime.fromMillisecondsSinceEpoch(IptvSettings.epgXmlCacheTime);

    final isCacheValid = now.year == cacheAt.year && now.month == cacheAt.month && now.day == cacheAt.day;

    if (isCacheValid) {
      final cache = await _getCacheXml();
      if (cache != null && cache.isNotEmpty) {
        _logger.debug('使用缓存xml');
        return cache;
      }
    }

    // 1点前，远程epg可能未更新，优先用旧缓存
    if (now.hour < 1) {
      final oldCache = await _getCacheXml();
      if (oldCache != null && oldCache.isNotEmpty) {
        _logger.debug('未到1点，使用旧缓存xml');
        return oldCache;
      }
      _logger.debug('未到1点且无旧缓存，尝试远程获取');
    }

    final xml = await _fetchXml();

    if (xml.isNotEmpty) {
      final cacheFile = await _getCacheXmlFile();
      await cacheFile.writeAsString(xml);
      IptvSettings.epgXmlCacheTime = now.millisecondsSinceEpoch;
      IptvSettings.epgCacheHash = 0;
      return xml;
    }

    // 远程获取失败，用旧缓存兜底
    final oldCache = await _getCacheXml();
    if (oldCache != null && oldCache.isNotEmpty) {
      _logger.debug('远程获取失败，使用旧缓存');
      return oldCache;
    }

    return '';
  }

  /// 解析epg
  static Future<List<Epg>> _parseFromXml(String xml, List<String> filteredChannels) async {
    _logger.debug('开始解析epg');
    final startAt = DateTime.now().millisecondsSinceEpoch;

    try {
      final epgList = await compute(_parseEpgInIsolate, [xml, filteredChannels]);

      _logger.debug('解析epg完成，共${epgList.length}个频道，耗时：${DateTime.now().millisecondsSinceEpoch - startAt}ms');
      return epgList;
    } catch (e, st) {
      _logger.handle(e, st);
      return [];
    }
  }

  /// 获取缓存文件
  static Future<File> _getCacheFile() async {
    return File('${(await getTemporaryDirectory()).path}/epg.json');
  }

  /// 获取缓存epg
  static Future<List<Epg>?> _getCache() async {
    try {
      final cacheFile = await _getCacheFile();
      if (await cacheFile.exists()) {
        final str = await cacheFile.readAsString();
        List<dynamic> jsonList = jsonDecode(str);
        return jsonList.map((e) => Epg.fromJson(e)).toList();
      }

      return null;
    } catch (e, st) {
      _logger.handle(e, st);
      return null;
    }
  }

  /// 仅从缓存获取epg（无网络请求）
  static Future<List<Epg>?> getCachedOnly(List<String> filteredChannels) async {
    if (!IptvSettings.epgEnable) return null;
    if (filteredChannels.isEmpty) return null;

    final hashcode = filteredChannels.map((str) => str.hashCode).reduce((value, element) => value ^ element);
    if (IptvSettings.epgCacheHash == hashcode) {
      return await _getCache();
    }
    return null;
  }

  /// 刷新并获取epg
  static Future<List<Epg>> refreshAndGet(List<String> filteredChannels) async {
    if (!IptvSettings.epgEnable) return [];
    if (filteredChannels.isEmpty) return [];

    final xml = await _refreshAndGetXml();
    if (xml.isEmpty) return [];

    final hashcode = filteredChannels.map((str) => str.hashCode).reduce((value, element) => value ^ element);
    if (IptvSettings.epgCacheHash == hashcode) {
      final cache = await _getCache();
      if (cache != null) {
        _logger.debug('使用缓存epg');
        return cache;
      }
    }
    
    final epgList = await _parseFromXml(xml, filteredChannels);

    final cacheFile = await _getCacheFile();
    await cacheFile.writeAsString(jsonEncode(epgList.map((e) => e.toJson()).toList()));
    IptvSettings.epgCacheHash = hashcode;

    return epgList;
  }
}

/// compute 要求的顶层函数，在 isolate 中解析 EPG XML
List<Epg> _parseEpgInIsolate(List<dynamic> message) {
  final xml = message[0] as String;
  final filteredChannels = message[1] as List<String>;

  int parseTime(String? time) {
    if (time == null || time.length < 14) return 0;
    return DateTime(
      int.parse(time.substring(0, 4)),
      int.parse(time.substring(4, 6)),
      int.parse(time.substring(6, 8)),
      int.parse(time.substring(8, 10)),
      int.parse(time.substring(10, 12)),
      int.parse(time.substring(12, 14)),
    ).millisecondsSinceEpoch;
  }

  final doc = XmlDocument.parse(xml);
  final tvEl = doc.getElement('tv');

  // 转 Set 再过滤：EPG 里的 <programme> 通常是几万到几十万量级，
  // 用 List.contains 会让整次解析退化成 O(n·m)。
  final channelSet = filteredChannels.toSet();

  final epgMap = <String, Epg>{};
  tvEl?.childElements.forEach((el) {
    final id = el.getAttribute('id');

    if (id != null) {
      final channelName = el.getElement('display-name')?.innerText ?? '';

      if (channelSet.contains(channelName)) {
        epgMap[id] = Epg(channel: channelName, programmes: []);
      }
    } else {
      final channel = el.getAttribute('channel');

      if (epgMap.containsKey(channel)) {
        final start = parseTime(el.getAttribute('start'));
        final stop = parseTime(el.getAttribute('stop'));
        final title = el.getElement('title')?.innerText ?? '';

        epgMap[channel]!.programmes.add(EpgProgramme(start: start, stop: stop, title: title));
      }
    }
  });

  return epgMap.values.toList();
}
