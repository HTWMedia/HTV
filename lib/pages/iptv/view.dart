import 'dart:async';

import 'package:fijkplayer_ijkfix/fijkplayer_ijkfix.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get_it/get_it.dart';
import 'package:mobx/mobx.dart';
import 'package:video_player_example/common/index.dart';
import 'package:video_player_example/common/widgets/easy_keyboard_listener.dart';
import 'package:video_player_example/pages/index.dart';
import 'package:video_player_example/pages/panel/widgets/iptv_ch.dart';
import 'package:video_player_example/pages/panel/widgets/iptv_info.dart';
import 'package:collection/collection.dart';

import '../../common/utils/debounce.dart';

final _logger = LoggerUtil.create(['直播播放']);

class IptvPage extends StatefulWidget {
  const IptvPage({super.key});

  @override
  State<IptvPage> createState() => _IptvPageState();
}

class _IptvPageState extends State<IptvPage> with WidgetsBindingObserver {
  final playerStore = GetIt.I<PlayerStore>();
  final iptvStore = GetIt.I<IptvStore>();
  final updateStore = GetIt.I<UpdateStore>();

  // MobX 资源清理列表
  final List<ReactionDisposer> _disposers = [];

  // 将 Debounce 提升为类成员，便于在 dispose 中清理
  final Debounce _debounce = Debounce(duration: const Duration(milliseconds: 100));

  // 上次播放的频道下标单独去抖写盘：它是同步刷 SharedPreferences，
  // 连按一次换台就是几十次磁盘写，没必要实时落盘。
  final Debounce _prefsDebounce = Debounce(duration: const Duration(seconds: 1));

  Timer? _refreshTimer;
  final _focusNode = FocusNode();
  /// 本次换台已经试过的源
  ///
  /// 配合 [SourceHealthUtil.ordered] 逐个往下试，而不是按下标盲轮转：坏源排在后
  /// 面，不必每次进这个台都把前面几条死源重新踩一遍起播超时（默认 12s/条）。
  final Set<String> _triedSources = {};
  int _switchAttempts = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initData();

    _startAutoRefresh();
  }

  /// 记录最后播放的频道下标
  ///
  /// 由 [_prefsDebounce] 去抖调用：连按换台时不必每次都同步写盘。
  void _saveLastIptvIdx() {
    final idx = iptvStore.iptvList.indexOf(iptvStore.currentIptv);
    if (idx >= 0) IptvSettings.initialIptvIdx = idx;
  }

  @override
  void dispose()  {
    // 1. 清理 MobX Reactions
    for (var disposer in _disposers) {
      disposer();
    }

    // 2. 清理 Debounce 资源 (调用新添加的方法)
    _debounce.cancel();
    _prefsDebounce.cancel();
    // 页面退出前把最后播放位置落盘，避免去抖窗口内的改动丢失
    _saveLastIptvIdx();

    _stopAutoRefresh();
    _infoHideTimer?.cancel();
    _infoHideTimer = null;

    WidgetsBinding.instance.removeObserver(this);
    _focusNode.dispose();
      playerStore.disposePlayer();
      super.dispose();
  }

  /// 🔹监听应用生命周期，按 Home 键时应用进入后台
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // App 从后台回到前台：立即刷新一次（可选），并重启定时器
      // 理由：App在后台时，定时器可能被系统暂停或杀死，
      // 用户回来时通常希望看到最新数据。
      _logger.debug("App resumed: Refreshing and restarting timer");
      iptvStore.refreshIptvList();
      // 重建出来的是一个空播放器，必须重新起播当前频道，
      // 否则回到前台只有黑屏，直到用户手动换台才恢复。
      // playIptv 必须排在 reinitPlayer（内部会预热 option）之后。
      playerStore.reinitPlayer().then((_) {
        if (mounted && iptvStore.currentIptv.name.isNotEmpty) {
          return playerStore.playIptv(iptvStore.currentIptv);
        }
      });
      _startAutoRefresh();
    }
    else if (state == AppLifecycleState.paused) {
      // 应用进入后台，按 Home 键也会触发
      // 后台随时可能被系统回收，先把播放位置落盘
      _prefsDebounce.cancel();
      _saveLastIptvIdx();
      playerStore.disposePlayer();
      // 🔹退出当前页面
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  void _startAutoRefresh() {
    // 先取消旧的，防止重复
    _stopAutoRefresh();

    // 设定2小时的定时器
    _refreshTimer = Timer.periodic(const Duration(hours: 2), (timer) {
      _logger.debug("Auto refreshing IPTV list...");
      iptvStore.refreshIptvList();
    });
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// 单源频道的最大重试次数
  ///
  /// 原来尝试上限直接等于源数量，单源频道失败一次就弹出「所有直播源均不可用」，
  /// 可是用户是拿 ffplay 验证过这个源能播的 —— 网络抖动、首次握手慢这类偶发失败
  /// 被一棍子打死，App 就此再也不重试，界面一直留在转圈。
  /// 单源也要留几次重试机会。
  static const int _singleSourceMaxAttempts = 3;

  Future<void> _switchToNextAvailableSource() async {
    // 防止 error 和 freeze 同时触发导致双重切源
    if (playerStore.isSwitching) return;
    playerStore.isSwitching = true;

    // 源串里夹杂空片段时不要把它当一条可用源
    final sources = iptvStore.currentIptv.url
        .split(';')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (sources.isEmpty) {
      playerStore.isSwitching = false;
      return;
    }

    // 多源时轮两圈（每个源都有不止一次机会），单源时退化为固定重试次数
    final maxAttempts =
        sources.length > 1 ? sources.length * 2 : _singleSourceMaxAttempts;

    // 所有源都试过了，停止重试
    if (_switchAttempts >= maxAttempts) {
      _logger.warning("已轮试 $maxAttempts 次仍无法播放，停止重试");
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(sources.length > 1
              ? "所有直播源均不可用"
              : "该直播源暂不可用，请稍后重试"),
          duration: const Duration(milliseconds: 1500),
        ));
      playerStore.isSwitching = false;
      return;
    }

    // 健康度最好的排前面，逐个往下试；跳过本次已经尝试过的
    // （含刚播失败的那条 —— 它由 playerStore 记在 currentUrl 里）。
    final ordered = SourceHealthUtil.ordered(sources);
    final skipped = <String>{
      ..._triedSources,
      if (playerStore.currentUrl.isNotEmpty) playerStore.currentUrl,
    };
    final next = ordered.firstWhere((u) => !skipped.contains(u),
        orElse: () => ordered[_switchAttempts % ordered.length]);
    _triedSources.add(next);
    _switchAttempts++;

    final current = iptvStore.currentIptv;
    final newIptv = Iptv(
      idx: current.idx,
      channel: current.channel,
      groupIdx: current.groupIdx,
      name: current.name,
      url: next,
      tvgName: current.tvgName,
      // 同一个频道换备用源，回看能力不变
      catchup: current.catchup,
      catchupSource: current.catchupSource,
      catchupDays: current.catchupDays,
    );

    playerStore.isSwitching = false;
    await playerStore.playIptv(newIptv);
  }

  Future<void> _initData() async {
    playerStore.initPlayer(
      onFreeze: () {
        if (playerStore.isSwitching) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text("播放卡顿，尝试切换源..."),
            duration: Duration(milliseconds: 1500),
          ));
        _switchToNextAvailableSource();
      },
      onError: () {
        if (playerStore.isSwitching) return;
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(const SnackBar(
            content: Text("播放错误，尝试切换源..."),
            duration: Duration(milliseconds: 1500),
          ));
        _switchToNextAvailableSource();
      },
    );

    // 回看录像播完后回到直播
    playerStore.onPlaybackEnd = () {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(
          content: Text("回看结束，回到直播"),
          duration: Duration(milliseconds: 1500),
        ));
      playerStore.playIptv(iptvStore.currentIptv);
    };

    // 追踪 currentIptv 变化，处理播放逻辑
    final iptvChangeDisposer = reaction((_) {
      return iptvStore.currentIptv;
    }, (iptv) async {
      iptvStore.iptvInfoVisible = true;
      _triedSources.clear();
      _switchAttempts = 0;
      playerStore.isSwitching = false;

      _debounce.debounce(() async {
        _prefsDebounce.debounce(_saveLastIptvIdx);

        await playerStore.playIptv(iptvStore.currentIptv);
        _infoHideTimer?.cancel();
        _infoHideTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && iptv == iptvStore.currentIptv) {
            iptvStore.iptvInfoVisible = false;
          }
        });
      });
    });
// 存储清理函数
    _disposers.add(iptvChangeDisposer);


    // 追踪 iptvList 变化，刷新 EPG
    final listChangeDisposer = reaction((_) => iptvStore.iptvList, (list) {
      iptvStore.refreshEpgList();

      // 补起播：以前只有 _initData 末尾会挑一次首频道，
      // 首次拉源失败后即使按 OK 重试成功，也不会自动播放，界面停在失败提示上。
      if (list.isNotEmpty && iptvStore.currentIptv.url.isEmpty) {
        iptvStore.currentIptv =
            list.elementAtOrNull(IptvSettings.initialIptvIdx) ?? list.first;
      }
    });
    // 存储清理函数
    _disposers.add(listChangeDisposer);

    // 并行执行：获取直播源 + 预热播放器
    await Future.wait([
      iptvStore.refreshIptvList(),
      playerStore.warmUp(),
    ]);

    _logger.debug('准备设置首频道: ipetvList长度=${iptvStore.iptvList.length}, initialIptvIdx=${IptvSettings.initialIptvIdx}');
    if (iptvStore.iptvList.isNotEmpty) {
      final first = iptvStore.iptvList.elementAtOrNull(IptvSettings.initialIptvIdx) ??
          iptvStore.iptvList.first;
      _logger.debug('设置当前频道: ${first.name}');
      iptvStore.currentIptv = first;
    }
    _logger.debug('首频道设置完成');

    updateStore.loadCurrentVersion();
    updateStore.refreshLatestRelease();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildGestureListener(
        child: Container(
          color: Colors.transparent,
          child: Stack(
            children: [
              _buildPlayer(),
              _buildIptvInfo(),
              _buildKeyboardListener(),
              _buildChannelSelect(),
              _buildListPlaceholder(),
            ],
          ),
        ),
      ),
    );
  }

  /// 播放器主界面
  Widget _buildPlayer() {
    return Focus(
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: Observer(
        builder: (_) {
          return Center(
            child: AspectRatio(
              aspectRatio: playerStore.aspectRatio ?? 16 / 9,
              child: FijkView(
                player: playerStore.player,
                fit: FijkFit.fill,
                color: Colors.black,
              ),
            ),
          );
        },
      ),
    );
  }

  /// 当前直播源信息
  Widget _buildIptvInfo() {
    return Observer(
      builder: (_) =>
      iptvStore.iptvInfoVisible
          ? Stack(
        children: [
          // 频道号
          //
          // 输入数字选台时右上角要让给待确认的频道号串（_buildChannelSelect）：
          // 两者都是 top:20 / right:20 的 90.sp 大字，同时出现会直接叠印成一团。
          if (iptvStore.channelNo.isEmpty)
            Positioned(
              top: 20.h,
              right: 20.w,
              child: PanelIptvChannel(
                  iptvStore.currentIptv.channel.toString().padLeft(2, '0')),
            ),
          // 频道信息
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20).r,
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(20).r,
                    decoration: BoxDecoration(
                      color: AppTheme.bgFaded(context, 0.8),
                      borderRadius: BorderRadius
                          .circular(20)
                          .r,
                    ),
                    child: PanelIptvInfo(epgShowFull: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      )
          : const SizedBox.shrink(),
    );
  }

  /// 键盘事件监听
  Widget _buildKeyboardListener() {
    return EasyKeyboardListener(
      autofocus: true,
      focusNode: _focusNode,
      onKeyTap: {
        // select 的短按在 keyUp 判定（见下方注释），这里只是借按下时机
        // 清掉上一次长按残留的标志，避免下一次短按被误吞。
        // 返回 false = 不消费，事件继续由 focus 链处理，与不挂这个键等价。
        LogicalKeyboardKey.select: () {
          _longSelectFired = false;
          return false;
        },
        LogicalKeyboardKey.arrowUp: () {
          if (IptvSettings.channelChangeFlip) {
            iptvStore.currentIptv = iptvStore.getNextIptv();
          } else {
            iptvStore.currentIptv = iptvStore.getPrevIptv();
          }
          return true;
        },
        LogicalKeyboardKey.arrowDown: () {
          if (IptvSettings.channelChangeFlip) {
            iptvStore.currentIptv = iptvStore.getPrevIptv();
          } else {
            iptvStore.currentIptv = iptvStore.getNextIptv();
          }
          return true;
        },
        LogicalKeyboardKey.arrowLeft: () { iptvStore.currentIptv = iptvStore.getPrevGroupIptv(); return true; },
        LogicalKeyboardKey.arrowRight: () { iptvStore.currentIptv = iptvStore.getNextGroupIptv(); return true; },
        LogicalKeyboardKey.settings: () { _openSettings(); return true; },
        LogicalKeyboardKey.contextMenu: () { _openSettings(); return true; },
        LogicalKeyboardKey.help: () { _openSettings(); return true; },
        LogicalKeyboardKey.digit0: () { iptvStore.inputChannelNo('0'); return true; },
        LogicalKeyboardKey.digit1: () { iptvStore.inputChannelNo('1'); return true; },
        LogicalKeyboardKey.digit2: () { iptvStore.inputChannelNo('2'); return true; },
        LogicalKeyboardKey.digit3: () { iptvStore.inputChannelNo('3'); return true; },
        LogicalKeyboardKey.digit4: () { iptvStore.inputChannelNo('4'); return true; },
        LogicalKeyboardKey.digit5: () { iptvStore.inputChannelNo('5'); return true; },
        LogicalKeyboardKey.digit6: () { iptvStore.inputChannelNo('6'); return true; },
        LogicalKeyboardKey.digit7: () { iptvStore.inputChannelNo('7'); return true; },
        LogicalKeyboardKey.digit8: () { iptvStore.inputChannelNo('8'); return true; },
        LogicalKeyboardKey.digit9: () { iptvStore.inputChannelNo('9'); return true; },
      },
      onKeyLongTap: {
        LogicalKeyboardKey.select: () {
          _longSelectFired = true;
          _openSettings();
          return true;
        },
      },
      onKeyRepeat: {
        LogicalKeyboardKey.arrowUp: () {
          if (IptvSettings.channelChangeFlip) {
            iptvStore.currentIptv = iptvStore.getNextIptv();
          } else {
            iptvStore.currentIptv = iptvStore.getPrevIptv();
          }
          return true;
        },
        LogicalKeyboardKey.arrowDown: () {
          if (IptvSettings.channelChangeFlip) {
            iptvStore.currentIptv = iptvStore.getPrevIptv();
          } else {
            iptvStore.currentIptv = iptvStore.getNextIptv();
          }
          return true;
        },
      },
      // OK 键改为松手触发：若按下瞬间就弹出面板，遥控器后续的 repeat 事件
      // 会被面板里的列表接走，表现为"面板刚打开就自动选台又关掉"。
      // 这里与 TwoDimensionListView 的长按判定保持一致。
      onKeyUp: {
        LogicalKeyboardKey.enter: () { _openPanel(); return true; },
        LogicalKeyboardKey.select: () {
          // 长按已经把设置页弹出来了，松手不再补一个频道面板
          if (_longSelectFired) {
            _longSelectFired = false;
            return true;
          }
          _openPanel();
          return true;
        },
      },
      child: const SizedBox.expand(),
    );
  }

  /// 手势事件监听
  Widget _buildGestureListener({required Widget child}) {
    return SwipeGestureDetector(
      onSwipeUp: () => iptvStore.currentIptv = iptvStore.getNextIptv(),
      onSwipeDown: () => iptvStore.currentIptv = iptvStore.getPrevIptv(),
      // onDragLeft: () => iptvStore.currentIptv = iptvStore.getPrevGroupIptv(),
      // onDragRight: () => iptvStore.currentIptv = iptvStore.getNextGroupIptv(),
      child: GestureDetector(
        // 单击必须「立刻」生效：只要同一个 GestureDetector 上还挂着 onDoubleTap，
        // Flutter 就要等约 300ms 的双击判定窗口过去才敢回调 onTap，
        // 表现为按 OK 开频道面板有明显迟滞。打开设置改由长按承担，
        // 遥控器上另外保留了 settings / contextMenu / help 键这一路。
        onTap: () {
          _focusNode.requestFocus();
          _openPanel();
        },
        onLongPress: () {
          HapticFeedback.mediumImpact();
          _focusNode.requestFocus();
          _openSettings();
        },
        child: child,
      ),
    );
  }

  /// 源列表尚未就绪时的占位层
  ///
  /// 以前拉不到源就是一块黑屏：既没有反馈也没有出路，用户只能一直等在那儿。
  /// 这里把"正在拉"和"拉失败"分开呈现，失败时给出重试入口。
  Widget _buildListPlaceholder() {
    return Observer(
      builder: (_) {
        final status = iptvStore.listStatus.value;
        if (status == IptvListStatus.ready) return const SizedBox.shrink();

        final failed = status == IptvListStatus.failed;

        return Positioned.fill(
          child: Container(
            color: AppTheme.scrim,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  failed
                      ? const Icon(Icons.error_outline,
                          color: Colors.orange, size: 56)
                      : CircularProgressIndicator(
                          color: AppTheme.fgFaded(context, AppTheme.oSecondary)),
                  SizedBox(height: 20.h),
                  Text(
                    failed ? '直播源获取失败' : '正在获取直播源…',
                    style: AppTheme.text(AppTheme.fg(context), 28.sp),
                  ),
                  if (failed) ...[
                    SizedBox(height: 10.h),
                    Text(
                      '请检查网络后，按 OK 键重试',
                      style: AppTheme.text(
                          AppTheme.fgFaded(context, AppTheme.oTertiary), 22.sp),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 数字选台
  Widget _buildChannelSelect() {
    return Positioned(
      top: 20.h,
      right: 20.w,
      child: Observer(
        builder: (_) => PanelIptvChannel(iptvStore.channelNo),
      ),
    );
  }

  bool panelOpened = false;
  bool settingsOpened = false;

  /// 本次按键是否已触发过长按打开设置。
  ///
  /// 这里存在的必要性：长按 select 走 onKeyLongTap，短按 select 走 onKeyUp，
  /// 但**松手一定会发 keyUp**。不记住的话，长按 OK 会先弹设置页、
  /// 松手再叠一层频道面板，返回要按两次。频道列表里（TwoDimensionListView）
  /// 用的是同一套判定，这里保持一致。
  bool _longSelectFired = false;

  /// 频道信息浮层隐藏定时器。
  ///
  /// 原来每次换台都 new 一个 3 秒 Timer 却不留引用：连续换台会让多个 timer 排队，
  /// 先到期的那个会把当前频道的信息浮层提前收掉。这里每次重新计时前先取消旧的，
  /// 页面销毁时再统一取消，避免回调打在已销毁的 State 上。
  Timer? _infoHideTimer;

  void _openPanel() {
    // 列表还没就绪时面板是空的，此时 OK 键的语义换成"重试"
    if (iptvStore.listStatus.value != IptvListStatus.ready) {
      iptvStore.refreshIptvList();
      return;
    }
    if (!panelOpened) {
      panelOpened = true;
      NavigatorUtil.push(context, const PanelPage()).then((_) {
        panelOpened = false;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusNode.requestFocus();
        });
      });
    }
  }

  void _openSettings() {
    // 与 _openPanel 一样做防重入：settings / contextMenu / help 三个键加长按都指向这里，
    // 连按会在栈上压出多个设置页，返回时要按好几次才回得来。
    if (settingsOpened) return;
    settingsOpened = true;
    NavigatorUtil.push(context, const SettingsPage()).then((_) {
      settingsOpened = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    });
  }
}
