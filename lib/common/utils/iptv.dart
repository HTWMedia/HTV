import 'dart:convert';
import 'dart:io';

import 'package:video_player_example/common/utils/auth_cipher.dart';
import 'package:flutter/services.dart';
import 'package:video_player_example/common/index.dart';
import 'package:path_provider/path_provider.dart';


final _logger = LoggerUtil.create(['iptv']);

/// iptv工具类
class IptvUtil {
  IptvUtil._();

  static const _locationCacheKey = 'cached_location';

  /// 获取省名：缓存优先（持久化），首次才走网络
  static Future<String> getCurrentProvinceInfo() async {
    final cached = PrefsUtil.getString(_locationCacheKey);
    if (cached != null && cached.isNotEmpty) {
      _refreshLocationAsync();
      return cached;
    }
    return _fetchAndCacheLocation();
  }

  static Future<String> _fetchAndCacheLocation() async {
    final location = await _fetchLocation();
    if (location.isNotEmpty) {
      PrefsUtil.setString(_locationCacheKey, location);
    }
    return location;
  }

  static Future<void> _refreshLocationAsync() async {
    try {
      await _fetchAndCacheLocation();
    } catch (_) {}
  }

  /// 获取当前省份名，按优先级尝试多个接口
  static Future<String> _fetchLocation() async {
    RequestUtil.addOrUpdateHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Safari/537.36 Edg/133.0.0.0");

    // 1. ip138（默认首选）
    try {
      final resp = await RequestUtil.get("https://2026.ip138.com/");
      if (resp.contains("来自")) {
        return resp.split('来自：').last.split('</span>').first.trim();
      }
    } catch (_) {}

    // 2. ip-api.com（国际接口，返回中文）
    try {
      final resp = await RequestUtil.get("http://ip-api.com/json/?lang=zh-CN");
      if (resp.isNotEmpty) {
        final data = jsonDecode(resp);
        final region = data['regionName'] as String? ?? '';
        if (region.isNotEmpty) return region;
      }
    } catch (_) {}

    // 3. api.ip.sb（备选）
    try {
      final resp = await RequestUtil.get("https://api.ip.sb/geoip");
      if (resp.isNotEmpty) {
        final data = jsonDecode(resp);
        final region = data['region'] as String? ?? '';
        if (region.isNotEmpty) return region;
      }
    } catch (_) {}

    return '';
  }

  /// 获取内置远程直播源
  static Future<String> _fetchBuiltinSource() async {
    final t0 = DateTime.now().millisecondsSinceEpoch;

    // 壳源分离：接口地址来自配置，App 自身不含任何源数据。
    // 主动清空这个配置项即停用内置源，此时只加载用户在设置里填的自定义源。
    final api = IptvSettings.defaultIptvSourceApi;
    if (api.isEmpty) {
      _logger.debug('默认源服务已停用，跳过内置源');
      return '';
    }
    _logger.debug('获取内置直播源');

    try {
      var time = DateTime
          .now()
          .millisecondsSinceEpoch
          .toString();
      var plainText = "HTV-First" + time;
      // 鉴权串由 AuthCipher 生成。开源仓库里它是桩（返回空串），
      // 此时不携带 authorization 头，服务端按匿名请求返回公网列表。
      final token = AuthCipher.encrypt(plainText);
      if (token.isNotEmpty) {
        RequestUtil.addOrUpdateHeader("authorization", token);
      }

      // 位置信息不阻塞源获取：直接读缓存（首次为空串），后台异步刷新
      getCurrentProvinceInfo();
      var user = PrefsUtil.getString('assign_user');
      if (user == null || user.isEmpty) {
        // assets/assign.txt 是默认用户标识。自建仓库/改过 asset 的人那里可能没有这个文件，
        // 缺失时不能让整个取源流程崩掉 —— 退化成不带 u 参数的请求，服务端照样返回公网列表。
        try {
          user = (await rootBundle.loadString('assets/assign.txt')).trim();
          if (user.isNotEmpty) PrefsUtil.setString('assign_user', user);
        } catch (e) {
          _logger.debug('未找到 assets/assign.txt，本次请求不带用户标识: $e');
          user = '';
        }
      }
      final location = PrefsUtil.getString(_locationCacheKey) ?? '';

      final separator = api.contains('?') ? '&' : '?';
      var reqUrl = api + separator + 'appid=3704&time=' +
          time + "&sr=1&loc=" + location + "&u="+user;

      _logger.debug('获取内置直播源: $reqUrl');

      final t2 = DateTime.now().millisecondsSinceEpoch;
      var result = await RequestUtil.get(reqUrl);
      _logger.debug('请求内置直播源耗时: ${DateTime.now().millisecondsSinceEpoch - t2}ms');

      RequestUtil.removeHeader("authorization");

      _logger.debug('获取内置直播源总耗时: ${DateTime.now().millisecondsSinceEpoch - t0}ms');
      return result;
    } catch (e, st) {
      _logger.handle(e, st);
      rethrow;
    }
  }

  /// 自定义源缓存是否已失效（过期或源地址已变更）
  static bool isCustomSourceCacheStale() {
    final now = DateTime.now().millisecondsSinceEpoch;
    return now - IptvSettings.customIptvSourceCacheTime >= IptvSettings.iptvSourceCacheKeepTime ||
        IptvSettings.customIptvSourceCacheUrl != IptvSettings.customIptvSource;
  }

  /// 获取自定义直播源缓存文件
  static Future<File> _getCustomCacheFile() async {
    return File('${(await getTemporaryDirectory()).path}/custom.txt');
  }

  /// 读取自定义直播源缓存（仅当缓存地址与当前配置一致）
  static Future<String> _getCustomCache() async {
    if (IptvSettings.customIptvSourceCacheUrl != IptvSettings.customIptvSource) return '';
    try {
      final cacheFile = await _getCustomCacheFile();
      if (await cacheFile.exists()) {
        return await cacheFile.readAsString();
      }
    } catch (e, st) {
      _logger.handle(e, st);
    }
    return '';
  }

  /// 获取自定义远程直播源（缓存优先，失效时抓取并写缓存；抓取失败回退旧缓存）
  static Future<String> _getCustomSource() async {
    _logger.debug('获取自定义直播源: ${IptvSettings.customIptvSource}');

    final cache = await _getCustomCache();
    if (!isCustomSourceCacheStale() && cache.isNotEmpty) {
      _logger.debug('使用自定义源缓存');
      return cache;
    }

    try {
      final t2 = DateTime.now().millisecondsSinceEpoch;
      // wget.la 等缓存代理首次抓取(冷缓存)可能需 40s+，使用更长超时
      var result = await RequestUtil.get(IptvSettings.customIptvSource,
          timeout: const Duration(seconds: 60));
      _logger.debug('请求自定义直播源耗时: ${DateTime.now().millisecondsSinceEpoch - t2}ms');

      if (result.isNotEmpty) {
        final cacheFile = await _getCustomCacheFile();
        await cacheFile.writeAsString(result);
        IptvSettings.customIptvSourceCacheTime = DateTime.now().millisecondsSinceEpoch;
        IptvSettings.customIptvSourceCacheUrl = IptvSettings.customIptvSource;
        _logger.debug('已缓存自定义直播源');
      }
      return result;
    } catch (e) {
      _logger.error('获取自定义源失败: $e');
      if (cache.isNotEmpty) {
        _logger.debug('自定义源抓取失败，回退旧缓存');
        return cache;
      }
      return '';
    }
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

  /// 获取已缓存的源列表（无网络请求，内置源 + 自定义源缓存合并）
  static Future<List<IptvGroup>?> getCachedGroups() async {
    final builtinCache = await _getCache();
    final customCache = IptvSettings.customIptvSource.isNotEmpty ? await _getCustomCache() : '';
    if (builtinCache.isEmpty && customCache.isEmpty) return null;
    return buildMergedGroups(builtinCache, customCache);
  }

  /// 根据 allowedChannels 过滤分组
  static List<IptvGroup> _applySimplifyFilter(List<IptvGroup> groups) {
    final allowed = IptvSettings.allowedChannels;
    var channel = 0;

    return groups
        .map((g) {
          final filtered = <Iptv>[];
          for (final item in g.list) {
            final pass = allowed.isNotEmpty
                ? allowed.contains(item.name)
                : item.name.toLowerCase().startsWith('cctv') ||
                    item.name.endsWith('卫视');
            if (!pass) continue;
            filtered.add(Iptv(
              idx: filtered.length,
              channel: ++channel,
              groupIdx: g.idx,
              name: item.name,
              url: item.url,
              tvgName: item.tvgName,
              catchup: item.catchup,
              catchupSource: item.catchupSource,
              catchupDays: item.catchupDays,
            ));
          }
          return IptvGroup(idx: g.idx, name: g.name, list: filtered);
        })
        .where((g) => g.list.isNotEmpty)
        .toList();
  }

  /// 解析直播源
  static Future<List<IptvGroup>> _parseSource(String source,
      {bool filter = true}) async {
    try {
      var groups = await parseIptvSource(source);

      if (filter && IptvSettings.iptvSourceSimplify) {
        groups = _applySimplifyFilter(groups);
      }

      return groups;
    } catch (e, st) {
      _logger.handle(e, st);
      rethrow;
    }
  }

  /// 获取当前源所有频道名称（不应用精简过滤）
  static Future<List<String>> getAllChannelNames() async {
    final cache = await _getCache();
    if (cache.isEmpty) return [];
    final groups = await _parseSource(cache, filter: false);
    return groups.expand((g) => g.list.map((i) => i.name)).toList();
  }

  /// 同名频道去重合并（保留首次出现的频道，url 用 ; 连接）
  static List<IptvGroup> _mergeDuplicateChannels(List<IptvGroup> groups) {
    final nameToUrls = <String, String>{};
    final nameToGroupIdx = <String, ({int groupIdx, int idx})>{};
    final result = <IptvGroup>[];

    // 第一遍：收集所有频道的 url 并记录首次出现位置
    for (var group in groups) {
      for (var i = 0; i < group.list.length; i++) {
        final iptv = group.list[i];
        if (nameToUrls.containsKey(iptv.name)) {
          nameToUrls[iptv.name] = '${nameToUrls[iptv.name]};${iptv.url}';
        } else {
          nameToUrls[iptv.name] = iptv.url;
          nameToGroupIdx[iptv.name] = (groupIdx: group.idx, idx: i);
        }
      }
    }

    // 第二遍：重建分组，只保留首次出现的频道，并更新合并后的 url
    for (var group in groups) {
      final kept = <Iptv>[];
      for (var i = 0; i < group.list.length; i++) {
        final iptv = group.list[i];
        final firstPos = nameToGroupIdx[iptv.name]!;
        // 只在本组首次出现的位置保留
        if (firstPos.groupIdx == group.idx && firstPos.idx == i) {
          kept.add(Iptv(
            idx: kept.length,
            channel: 0,
            groupIdx: group.idx,
            name: iptv.name,
            url: nameToUrls[iptv.name]!,
            tvgName: iptv.tvgName,
            catchup: iptv.catchup,
            catchupSource: iptv.catchupSource,
            catchupDays: iptv.catchupDays,
          ));
        }
      }
      result.add(IptvGroup(idx: group.idx, name: group.name, list: kept));
    }

    return result.where((g) => g.list.isNotEmpty).toList();
  }

  /// 重排分组与频道索引，并保证索引与最终列表位置严格一致
  ///
  /// 前置的简化过滤（[_applySimplifyFilter]）与同名去重（[_mergeDuplicateChannels]）
  /// 会整组丢弃频道，但重建时保留了原始序号，导致 [IptvGroup.idx] / [Iptv.groupIdx]
  /// 不再等于实际下标——出现"空洞"，甚至大于列表长度。
  ///
  /// 而外层多处把它当作位置索引直接使用（频道面板的定位行、左右键切换分组），
  /// 一旦错位会高亮到错误的分组，或直接越界崩溃。这里按最终位置统一重排，
  /// 同时保持 [Iptv.channel] 的全局连号（供频道号显示与数字选台使用）。
  static List<IptvGroup> _reindex(List<IptvGroup> groups) {
    final result = <IptvGroup>[];
    var channel = 0;

    for (var g = 0; g < groups.length; g++) {
      final group = groups[g];
      final list = <Iptv>[];

      for (var i = 0; i < group.list.length; i++) {
        final old = group.list[i];
        list.add(Iptv(
          idx: i,
          channel: ++channel,
          groupIdx: g,
          name: old.name,
          url: old.url,
          tvgName: old.tvgName,
          catchup: old.catchup,
          catchupSource: old.catchupSource,
          catchupDays: old.catchupDays,
        ));
      }

      result.add(IptvGroup(idx: g, name: group.name, list: list));
    }

    return result;
  }

  /// 合并内置源与自定义源分组：组名加"(自定义)"后缀、同名频道去重合并、全局重排频道号
  static Future<List<IptvGroup>> buildMergedGroups(String builtinSource, String customSource) async {
    var builtinGroups = builtinSource.isEmpty ? <IptvGroup>[] : await _parseSource(builtinSource);
    var customGroups = customSource.isEmpty ? <IptvGroup>[] : await _parseSource(customSource);

    for (var group in customGroups) {
      final newIdx = builtinGroups.length;
      final newList = group.list.map((iptv) => Iptv(
        idx: iptv.idx,
        channel: iptv.channel,
        groupIdx: newIdx,
        name: iptv.name,
        url: iptv.url,
        tvgName: iptv.tvgName,
        catchup: iptv.catchup,
        catchupSource: iptv.catchupSource,
        catchupDays: iptv.catchupDays,
      )).toList();
      builtinGroups.add(IptvGroup(
        idx: newIdx,
        name: '${group.name}(自定义)',
        list: newList,
      ));
    }

    builtinGroups = _mergeDuplicateChannels(builtinGroups);
    // 前置步骤丢弃过分组，必须按最终位置重排索引后才能对外暴露
    return _reindex(builtinGroups);
  }

  /// 刷新并获取直播源（内置源 + 自定义源合并，均缓存优先）
  static Future<List<IptvGroup>> refreshAndGet() async {
    final t0 = DateTime.now().millisecondsSinceEpoch;

    // 1. 获取内置源（缓存优先）
    String builtinSource = '';
    if (t0 - IptvSettings.iptvSourceCacheTime < IptvSettings.iptvSourceCacheKeepTime) {
      final cache = await _getCache();
      if (cache.isNotEmpty) {
        _logger.debug('使用缓存直播源');
        builtinSource = cache;
      }
    }

    if (builtinSource.isEmpty) {
      final source = await _fetchBuiltinSource();
      if (source.isNotEmpty) {
        final cacheFile = await _getCacheFile();
        await cacheFile.writeAsString(source);
        IptvSettings.iptvSourceCacheTime = t0;
        builtinSource = source;
      }
    }

    // 2. 获取自定义源（缓存优先）
    final customSource = IptvSettings.customIptvSource.isNotEmpty ? await _getCustomSource() : '';

    // 3. 合并、去重、重排频道号
    final result = await buildMergedGroups(builtinSource, customSource);

    _logger.debug('刷新直播源总耗时: ${DateTime.now().millisecondsSinceEpoch - t0}ms');

    return result;
  }
}