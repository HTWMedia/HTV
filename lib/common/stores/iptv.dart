import 'dart:async';

import 'package:collection/collection.dart';
import 'package:get_it/get_it.dart';
import 'package:mobx/mobx.dart';
import 'package:video_player_example/common/index.dart';

part 'iptv.g.dart';

/// 直播源列表的加载状态
///
/// 以前拉源失败和"还在拉"都表现为同一个东西：空列表 + 黑屏。
/// 界面上没有任何反馈，也没有重试入口，用户只能干看着"一直在加载"。
enum IptvListStatus {
  /// 还没有可用的列表，正在拉取
  loading,

  /// 已有可用列表
  ready,

  /// 拉取失败（列表为空）
  failed,
}

class IptvStore = IptvStoreBase with _$IptvStore;

abstract class IptvStoreBase with Store {
  /// 直播源分组列表
  @observable
  List<IptvGroup> iptvGroupList = [];

  /// 直播源列表（派生自 iptvGroupList）
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

  /// 节目单索引（频道名 → Epg），用于 O(1) 查找
  Map<String, Epg> _epgMap = {};

  /// 收藏的频道名集合
  /// 使用 ObservableSet：自带 action 语义且可直接在 Observer 中追踪，无需重新生成 .g.dart
  final ObservableSet<String> favoriteNames = ObservableSet<String>();

  /// 收藏在本地存储中的 key
  static const String favoritePrefsKey = 'iptv_favorite_channels';

  /// 读取本地收藏
  Future<void> loadFavorites() async {
    final saved = PrefsUtil.getStringList(favoritePrefsKey) ?? <String>[];
    favoriteNames
      ..clear()
      ..addAll(saved);
  }

  /// 是否已收藏
  bool isFavorite(Iptv iptv) => favoriteNames.contains(iptv.name);

  /// 构建名称索引时的源列表快照，用于判断索引是否过期
  List<IptvGroup>? _indexSource;

  /// 频道名 → 频道的映射（带缓存）
  ///
  /// 面板每一帧都会读 favoriteIptvList / 收藏判断，没有缓存就是每帧重建整张哈希表。
  /// 源列表只在 refreshIptvList 里整体赋值（没有原地增删），
  /// 因此用实例 identity 判断过期是安全的。
  Map<String, Iptv> get _byName {
    final src = iptvGroupList;
    if (_nameIndex == null || !identical(_indexSource, src)) {
      _indexSource = src;
      _nameIndex = <String, Iptv>{
        for (final e in src.expand((g) => g.list)) e.name: e,
      };
    }
    return _nameIndex!;
  }

  Map<String, Iptv>? _nameIndex;

  /// 收藏的频道列表（按添加顺序；源列表中已不存在的频道会被自动过滤）
  /// 注意：这是普通 getter，依赖 favoriteNames 与 iptvList，在 Observer 中可正常响应
  List<Iptv> get favoriteIptvList {
    if (favoriteNames.isEmpty) return const [];
    final byName = _byName;
    return favoriteNames.map((n) => byName[n]).whereType<Iptv>().toList();
  }

  /// 直播源列表加载状态
  ///
  /// 用 [Observable] 而非 `@observable`，这样不必重新生成 .g.dart。
  final Observable<IptvListStatus> listStatus =
      Observable(IptvListStatus.loading);

  /// 切换收藏，返回切换后是否为收藏状态
  Future<bool> toggleFavorite(Iptv iptv) async {
    final removed = favoriteNames.remove(iptv.name);
    if (!removed) favoriteNames.add(iptv.name);
    await PrefsUtil.setStringList(favoritePrefsKey, favoriteNames.toList());
    return !removed;
  }

  /// 获取上一个直播源
  ///
  /// 列表为空时要守得住：currentIptv 此时还是 Iptv.empty，indexOf 返回 -1，
  /// prevIdx 是 -2，`iptvList.last` 会抛 Bad state: No element。
  /// 首次启动还没拉到源、或自定义源为空时按上下键就会走到这条路径，
  /// 而 playerStore 的兜底播放在键盘回调之后，挡不住这次崩溃。
  Iptv getPrevIptv([Iptv? iptv]) {
    final list = iptvList;
    if (list.isEmpty) return iptv ?? currentIptv;

    final target = iptv ?? currentIptv;
    final currentIdx = list.indexOf(target);
    final prevIdx = currentIdx - 1;
    return prevIdx < 0 ? list.last : list[prevIdx];
  }

  /// 获取下一个直播源（[getPrevIptv] 的空列表守卫同理）
  Iptv getNextIptv([Iptv? iptv]) {
    final list = iptvList;
    if (list.isEmpty) return iptv ?? currentIptv;

    final target = iptv ?? currentIptv;
    final currentIdx = list.indexOf(target);
    final nextIdx = currentIdx + 1;
    return nextIdx >= list.length ? list.first : list[nextIdx];
  }

  /// 取指定分组的首个频道，越界或分组为空时回退到当前频道
  ///
  /// 历史数据或第三方源的 groupIdx 可能与列表位置不一致，
  /// 直接按下标取元素会越界崩溃，导致遥控器完全失灵。
  Iptv _firstOfGroup(int groupIdx) {
    if (iptvGroupList.isEmpty) return currentIptv;
    final group = iptvGroupList.elementAtOrNull(groupIdx.clamp(0, iptvGroupList.length - 1));
    if (group == null || group.list.isEmpty) return currentIptv;
    return group.list.first;
  }

  /// 获取上一个分组直播源
  Iptv getPrevGroupIptv([Iptv? iptv]) {
    final prevIdx = (iptv?.groupIdx ?? currentIptv.groupIdx) - 1;
    return _firstOfGroup(prevIdx < 0 ? iptvGroupList.length - 1 : prevIdx);
  }

  /// 获取下一个分组直播源
  Iptv getNextGroupIptv([Iptv? iptv]) {
    final nextIdx = (iptv?.groupIdx ?? currentIptv.groupIdx) + 1;
    return _firstOfGroup(nextIdx >= iptvGroupList.length ? 0 : nextIdx);
  }

  /// 刷新直播源列表（优先缓存，过期时后台静默更新）
  @action
  Future<void> refreshIptvList() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final builtinExpired = now - IptvSettings.iptvSourceCacheTime >= IptvSettings.iptvSourceCacheKeepTime;
    final customStale = IptvSettings.customIptvSource.isNotEmpty && IptvUtil.isCustomSourceCacheStale();
    final expired = builtinExpired || customStale;

    // 1. 有缓存时秒展示（即使已过期）
    final cached = await IptvUtil.getCachedGroups();
    if (cached != null) {
      listStatus.value =
          cached.isEmpty ? IptvListStatus.failed : IptvListStatus.ready;
      iptvGroupList = cached;
      if (!expired) return; // 缓存有效，完成
      _refreshFromNetwork(); // 后台静默刷新
      return;
    }

    // 2. 从未缓存过，等网络
    listStatus.value = IptvListStatus.loading;
    final fresh = await IptvUtil.refreshAndGet();
    listStatus.value =
        fresh.isEmpty ? IptvListStatus.failed : IptvListStatus.ready;
    iptvGroupList = fresh;
  }

  Future<void> _refreshFromNetwork() async {
    try {
      final fresh = await IptvUtil.refreshAndGet();
      if (fresh.isEmpty) {
        // 后台刷新拉不到东西（网络抖动、服务端异常）时保留现有列表：
        // 原来这里无脑覆盖，一次后台失败就把用户正在看的频道池清空，
        // 界面再也不回来，直到重启 App。
        return;
      }
      runInAction(() {
        iptvGroupList = fresh;
        listStatus.value = IptvListStatus.ready;
      });
    } catch (_) {}
  }

  /// 刷新节目单（缓存优先，无缓存时立即网络获取并异步更新界面）
  @action
  Future<void> refreshEpgList() async {
    final channels = iptvList.map((e) => e.tvgName).toList();

    // Phase 1: 立即从缓存获取
    final cached = await EpgUtil.getCachedOnly(channels);
    if (cached != null && cached.isNotEmpty) {
      epgList = cached;
      _epgMap = {for (var epg in cached) epg.channel: epg};
    }

    // Phase 2: 异步从网络获取最新数据，完成后自动更新UI
    EpgUtil.refreshAndGet(channels).then((freshList) {
      if (freshList.isNotEmpty) {
        runInAction(() {
          epgList = freshList;
          _epgMap = {for (var epg in freshList) epg.channel: epg};
        });
      }
    });
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

  /// 当前频道可用源列表
  ///
  /// 按健康度排序（[SourceHealthUtil.ordered]）：失败过且还在冷却期内的源排到后面，
  /// 手动切源时也就不会停在一个已知播不了的源上。
  /// 权重相同时保持后端下发的原始顺序，"源 X/Y"的显示才不会乱跳。
  List<String> get currentSources =>
      SourceHealthUtil.ordered(SourceHealthUtil.splitSources(currentIptv.url));

  /// 当前源序号
  @observable
  int currentSourceIndex = 0;

  /// 手动切换下一个源
  @action
  Future<void> switchToNextSource() async {
    if (currentSources.length <= 1) return;
    currentSourceIndex = (currentSourceIndex + 1) % currentSources.length;
    final newIptv = Iptv(
      idx: currentIptv.idx,
      channel: currentIptv.channel,
      groupIdx: currentIptv.groupIdx,
      name: currentIptv.name,
      url: currentSources[currentSourceIndex],
      tvgName: currentIptv.tvgName,
      // 同一个频道换备用源，回看能力不变
      catchup: currentIptv.catchup,
      catchupSource: currentIptv.catchupSource,
      catchupDays: currentIptv.catchupDays,
    );
    final playerStore = GetIt.I<PlayerStore>();
    await playerStore.playIptv(newIptv);
  }

  /// 指定频道的节目单（含已播出的往期节目，回看列表要用）
  List<EpgProgramme> getProgrammes(Iptv iptv) {
    epgList; // 建立 MobX 反应依赖
    return _epgMap[iptv.tvgName]?.programmes ?? const [];
  }

  // 获取节目单
  ({String current, String next}) getIptvProgrammes(Iptv iptv) {
    final now = DateTime.now().millisecondsSinceEpoch;

    epgList; // 建立 MobX 反应依赖
    final epg = _epgMap[iptv.tvgName];

    final currentProgramme = epg?.programmes.firstWhereOrNull((element) => element.start <= now && element.stop >= now);
    final nextProgramme = epg?.programmes.firstWhereOrNull((element) => element.start > now);

    return (current: currentProgramme?.title ?? '', next: nextProgramme?.title ?? '');
  }

  @computed
  ({String current, String next}) get currentIptvProgrammes {
    return getIptvProgrammes(currentIptv);
  }
}
