import 'dart:convert';

import '../models/iptv.dart';
import 'catchup.dart';

/// 直播源格式
enum IptvSourceFormat {
  /// JSON 数组（内置源）
  inline,

  /// m3u 订阅
  m3u,

  /// tvbox 文本
  tvbox,
}

/// 根据内容识别直播源格式（与是否配置自定义源无关）
IptvSourceFormat detectSourceFormat(String source) {
  final trimmed = source.trimLeft();
  if (trimmed.startsWith('[')) return IptvSourceFormat.inline;
  if (trimmed.startsWith('#EXTM3U')) return IptvSourceFormat.m3u;
  return IptvSourceFormat.tvbox;
}

/// 解析 m3u 直播源
Future<List<IptvGroup>> parseM3uSource(String source) async {
  var groupList = <IptvGroup>[];

  final lines = source.split('\n');

  // #EXTM3U 全局头可能带 catchup 声明（如 catchup="append"），作为所有频道的默认值
  var m3uHead = '';
  for (final line in lines) {
    if (line.startsWith('#EXTM3U')) {
      m3uHead = line;
      break;
    }
  }

  var channel = 0;
  for (final (lineIdx, line) in lines.indexed) {
    if (line.isEmpty || !line.startsWith('#EXTINF:')) {
      continue;
    }

    final groupName = RegExp('group-title="(.*?)"').firstMatch(line)?.group(
        1) ?? '其他';
    final name = line.split(',')[1];

    final group = groupList.firstWhere((it) => it.name == groupName,
        orElse: () {
          final group = IptvGroup(
              idx: groupList.length, name: groupName, list: []);
          groupList.add(group);
          return group;
        });

    // 频道行上的 catchup 属性可覆盖全局声明
    final catchupInfo = CatchupUtil.resolve(m3uHead, line);

    final iptv = Iptv(
      idx: group.list.length,
      channel: ++channel,
      groupIdx: group.idx,
      name: name,
      url: lines[lineIdx + 1],
      tvgName: RegExp('tvg-name="(.*?)"').firstMatch(line)?.group(1) ?? name,
      catchup: catchupInfo.type,
      catchupSource: catchupInfo.source,
      catchupDays: catchupInfo.days,
    );

    group.list.add(iptv);
  }

  return groupList;
}

/// 解析 tvbox 直播源
Future<List<IptvGroup>> parseTvboxSource(String source) async {
  var groupList = <IptvGroup>[];

  final lines = source.split('\n');

  var channel = 0;
  IptvGroup? group;
  for (final line in lines) {
    if (line.isEmpty) continue;
    if (line.startsWith('#')) continue;

    if (line.endsWith('#genre#')) {
      final groupName = line.split(',')[0];
      group = IptvGroup(idx: groupList.length, name: groupName, list: []);
      groupList.add(group);
    } else {
      List<String> separators = ['，'];
      final newLine = line.splitMapJoin(
        RegExp('[${separators.map((s) => '\\$s').join('')}]'),
        onMatch: (m) => ',',
        onNonMatch: (n) => n,
      );

      if (newLine.split(',').length < 2) continue;

      final name = newLine.split(',')[0];
      final url = newLine.split(',')[1];

      final iptv = Iptv(
        idx: group!.list.length,
        channel: ++channel,
        groupIdx: group.idx,
        name: name,
        url: url,
        tvgName: name,
      );

      group.list.add(iptv);
    }
  }

  return groupList;
}

/// 解析 inline(JSON) 直播源
///
/// 内置源（Web 的 tv/iptv4.json）就是这种格式，字段为
/// `title / url / grouptitle / groupidx`。
/// 回看相关的三个字段目前服务端并不下发，这里一并兼容：
/// 将来 `IPTVUpdateService` 补上 `catchup` / `catchupSource` / `catchupDays`
/// 后无需再改解析层。键名同时接受小驼峰与全小写两种写法。
Future<List<IptvGroup>> parseInlineSource(String source) async {
  var groupList = <IptvGroup>[];

  final lines = jsonDecode(source);
  var channel = 0;
  for (var i = 0; i < lines.length; i++) {
    final item = lines[i];
    final groupName = item['grouptitle'].toString().trim();
    final name = item["title"].toString().trim();
    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = item[k];
        if (v == null) continue;
        final s = v.toString().trim();
        if (s.isNotEmpty) return s;
      }
      return null;
    }

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
      url: item['url'].toString().trim(),
      tvgName: name,
      catchup: pick(['catchup', 'catchUp']) ?? '',
      catchupSource: pick(['catchupSource', 'catchupsource', 'catchup_source']) ?? '',
      catchupDays: int.tryParse(pick(['catchupDays', 'catchupdays', 'catchup_days']) ?? '1') ?? 1,
    );

    group.list.add(iptv);
  }

  return groupList;
}

/// 按内容识别格式并解析直播源
Future<List<IptvGroup>> parseIptvSource(String source) async {
  switch (detectSourceFormat(source)) {
    case IptvSourceFormat.inline:
      return parseInlineSource(source);
    case IptvSourceFormat.m3u:
      return parseM3uSource(source);
    case IptvSourceFormat.tvbox:
      return parseTvboxSource(source);
  }
}
