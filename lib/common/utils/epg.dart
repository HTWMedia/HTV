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

    if (now.year == cacheAt.year && now.month == cacheAt.month && now.day == cacheAt.day) {
      final cache = await _getCacheXml();

      if (cache != null) {
        _logger.debug('使用缓存xml');
        return cache;
      }
    } else {
      // 1点前，远程epg可能未更新
      if (now.hour < 1) {
        _logger.debug('未到1点，不刷新epg');
        return XmlBuilder().buildDocument().toXmlString();
      }
    }

    final xml = await _fetchXml();

    final cacheFile = await _getCacheXmlFile();
    await cacheFile.writeAsString(xml);
    IptvSettings.epgXmlCacheTime = now.millisecondsSinceEpoch;
    IptvSettings.epgCacheHash = 0; // 重置epg解析

    return xml;
  }

  /// 解析epg
  static List<Epg> _parseFromXml(String xml, List<String> filteredChannels) {
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

    final epgMap = <String, Epg>{};
    tvEl?.childElements.forEach((el) {
      final id = el.getAttribute('id');

      if (id != null) {
        final channelName = el.getElement('display-name')?.innerText ?? '';

        if (filteredChannels.contains(channelName)) {
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

  /// 刷新并获取epg
  static Future<List<Epg>> refreshAndGet(List<String> filteredChannels) async {
    if (!IptvSettings.epgEnable) return [];

    final xml = await _refreshAndGetXml();

    final hashcode = filteredChannels.map((str) => str.hashCode).reduce((value, element) => value ^ element);

    if (IptvSettings.epgCacheHash == hashcode) {
      final cache = await _getCache();

      if (cache != null) {
        _logger.debug('使用缓存epg');
        return cache;
      }
    }

    _logger.debug('开始解析epg');
    final startAt = DateTime.now().millisecondsSinceEpoch;
    final epgList = await compute((_) => _parseFromXml(xml, filteredChannels), 0);
    _logger.debug('解析epg完成，共${epgList.length}个频道，耗时：${DateTime.now().millisecondsSinceEpoch - startAt}ms');

    final cacheFile = await _getCacheFile();
    await cacheFile.writeAsString(jsonEncode(epgList.map((e) => e.toJson()).toList()));
    IptvSettings.epgCacheHash = hashcode;

    return epgList;
  }
}
