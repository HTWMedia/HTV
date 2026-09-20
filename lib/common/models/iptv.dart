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

  /// 回放类型（回看）。取自 m3u 的 `catchup` 属性：
  /// `append` = 把 [catchupSource] 追加到直播地址后；`default`/`shift`/`vod` = 直接用 [catchupSource] 作模板。
  /// 空字符串表示该频道不支持回看。
  late final String catchup;

  /// 回看地址模板，取自 m3u 的 `catchup-source`。
  /// 其中 `${(b)yyyyMMddHHmmss}` 为节目开始时间、`${(e)yyyyMMddHHmmss}` 为结束时间。
  late final String catchupSource;

  /// 可回看的天数，取自 `catchup-days`，未声明时为 1
  late final int catchupDays;

  Iptv({
    required this.idx,
    required this.channel,
    required this.groupIdx,
    required this.name,
    required this.url,
    required this.tvgName,
    this.catchup = '',
    this.catchupSource = '',
    this.catchupDays = 1,
  });

  /// 是否支持回看
  bool get supportCatchup => catchup.isNotEmpty && catchupSource.isNotEmpty;

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
