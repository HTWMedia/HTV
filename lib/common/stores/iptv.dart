import 'dart:async';

import 'package:collection/collection.dart';
import 'package:mobx/mobx.dart';
import 'package:video_player_example/common/index.dart';

part 'iptv.g.dart';

class IptvStore = IptvStoreBase with _$IptvStore;

abstract class IptvStoreBase with Store {
  /// 直播源分组列表
  @observable
  List<IptvGroup> iptvGroupList = [];

  /// 直播源列表
  @computed
  List<Iptv> get iptvList => iptvGroupList.expand((e) => e.list).toList();

  /// 当前直播源
  @observable
  Iptv currentIptv = Iptv.empty;

  /// 显示iptv信息
  @observable
  bool iptvInfoVisible = false;

  /// 选台频道号
  @observable
  String channelNo = '';

  /// 确认选台定时器
  Timer? confirmChannelTimer;

  /// 节目单
  @observable
  List<Epg>? epgList;

  /// 获取上一个直播源
  Iptv getPrevIptv([Iptv? iptv]) {
    final prevIdx = iptvList.indexOf(iptv ?? currentIptv) - 1;
    return prevIdx < 0 ? iptvList.last : iptvList.elementAt(prevIdx);
  }

  /// 获取下一个直播源
  Iptv getNextIptv([Iptv? iptv]) {
    final nextIdx = iptvList.indexOf(iptv ?? currentIptv) + 1;
    return nextIdx >= iptvList.length ? iptvList.first : iptvList.elementAt(nextIdx);
  }

  /// 获取上一个分组直播源
  Iptv getPrevGroupIptv([Iptv? iptv]) {
    final prevIdx = (iptv?.groupIdx ?? currentIptv.groupIdx) - 1;
    return prevIdx < 0 ? iptvGroupList.last.list.first : iptvGroupList.elementAt(prevIdx).list.first;
  }

  /// 获取下一个分组直播源
  Iptv getNextGroupIptv([Iptv? iptv]) {
    final nextIdx = (iptv?.groupIdx ?? currentIptv.groupIdx) + 1;
    return nextIdx >= iptvGroupList.length
        ? iptvGroupList.first.list.first
        : iptvGroupList.elementAt(nextIdx).list.first;
  }

  /// 刷新直播源列表
  @action
  Future<void> refreshIptvList() async {
    iptvGroupList = await IptvUtil.refreshAndGet();
  }

  @action
  Future<void> updateIptvList(String url) async {
    iptvGroupList=await IptvUtil.updateIPTV(url);
  }

  /// 刷新节目单
  @action
  Future<void> refreshEpgList() async {
    epgList = await EpgUtil.refreshAndGet(iptvList.map((e) => e.tvgName).toList());
  }

  /// 手动输入频道号
  void inputChannelNo(String no) {
    confirmChannelTimer?.cancel();

    channelNo += no;
    confirmChannelTimer = Timer(Duration(seconds: 4 - channelNo.length), () {
      final channel = int.tryParse(channelNo) ?? 0;
      final iptv = iptvList.firstWhere((e) => e.channel == channel, orElse: () => currentIptv);
      currentIptv = iptv;
      channelNo = '';
    });
  }

  // 获取节目单
  ({String current, String next}) getIptvProgrammes(Iptv iptv) {
    final now = DateTime.now().millisecondsSinceEpoch;

    final epg = epgList?.firstWhereOrNull((element) => element.channel == iptv.tvgName);

    final currentProgramme = epg?.programmes.firstWhereOrNull((element) => element.start <= now && element.stop >= now);
    final nextProgramme = epg?.programmes.firstWhereOrNull((element) => element.start > now);

    return (current: currentProgramme?.title ?? '', next: nextProgramme?.title ?? '');
  }

  @computed
  ({String current, String next}) get currentIptvProgrammes {
    return getIptvProgrammes(currentIptv);
  }
}
