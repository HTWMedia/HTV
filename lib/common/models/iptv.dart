/// 直播源
class Iptv {
  /// 序号
  late final int idx;

  /// 频道号
  late final int channel;

  /// 所属分组
  late final int groupIdx;

  /// 名称
  late final String name;

  /// 播放地址
  late final String url;

  /// tvg名称
  late final String tvgName;

  Iptv({
    required this.idx,
    required this.channel,
    required this.groupIdx,
    required this.name,
    required this.url,
    required this.tvgName,
  });

  @override
  String toString() {
    return 'Iptv{idx: $idx, channel: $channel, groupIdx: $groupIdx, name: $name, url: $url, tvgName: $tvgName}';
  }

  static Iptv get empty => Iptv(idx: 0, channel: 0, groupIdx: 0, name: '', url: '', tvgName: '');
}

/// 直播源分组
class IptvGroup {
  /// 序号
  late final int idx;

  /// 名称
  late final String name;

  /// 直播源列表
  late final List<Iptv> list;

  IptvGroup({required this.idx, required this.name, required this.list});

  @override
  String toString() {
    return 'IptvGroup{idx: $idx, name: $name, list: ${list.length}}';
  }

  static IptvGroup get empty => IptvGroup(idx: 0, name: '', list: []);
}
