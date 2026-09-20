import 'dart:async';
import 'package:fijkplayer_ijkfix/fijkplayer_ijkfix.dart';
import 'package:flutter/material.dart';
import 'package:mobx/mobx.dart';

import '../models/iptv.dart';
import '../utils/logger.dart';
import '../utils/source_health.dart';

part 'player.g.dart';

class PlayerStore = PlayerStoreBase with _$PlayerStore;

/// 播放状态
enum PlayerState {
  /// 等待播放
  waiting,

  /// 播放中
  playing,

  /// 播放失败
  failed,
}

final _logger = LoggerUtil.create(['播放器']);

abstract class PlayerStoreBase with Store {
  /// 播放器
  @observable
  FijkPlayer player = FijkPlayer();

  /// 宽高比
  @observable
  double? aspectRatio;

  /// 分辨率
  @observable
  Size resolution = Size.zero;

  /// 播放状态
  @observable
  PlayerState state = PlayerState.waiting;

  /// 错误信息
  @observable
  String errorInfo = '';

  Timer? _freezeTimer;
  VoidCallback? _onFreezeCallback;
  VoidCallback? _onErrorCallback;

  /// 起播超时：Dart 侧唯一的兜底手段
  ///
  /// native 的 prepare 是异步的。遇到「TCP 连得上但服务端不给数据」「DNS 解析挂住」
  /// 「防火墙直接丢包」这类半开连接时，ijkplayer 会长时间停在 [FijkState.asyncPreparing]：
  /// 既不到 prepared，也不报错。而卡顿检测 [_startFreezeCheck] **只在 prepared 之后**才启动，
  /// 状态没有变化也就不会有回调，于是整条链路既没有超时也没有重试 ——
  /// 这正是用户反馈的「进了 App 一直加载、不自动切源」。
  ///
  /// ffmpeg 的 http/tcp 默认读写超时是无限等待，指望 native 自己超时并不现实，
  /// 所以从按下播放这一刻起在 Dart 侧独立计时。
  /// 业务默认 12s；单测会临时改小，以免每次真等 12 秒。
  /// 之所以不是 const：测试要注入更短的时长，而 const 无法替换。
  static Duration startWatchdogTimeout = const Duration(seconds: 12);

  Timer? _watchdogTimer;

  /// 缓冲中断后允许自愈的宽限时长
  ///
  /// 播放器在缓冲耗尽的那一刻会主动推 [FijkPlayer.onBufferStateUpdate]，
  /// 不必等 [_startFreezeCheck] 的轮询来发现——那是 5 秒一查、还要连续两次
  /// 采样位置相同才判死，最快也要 10 秒。
  ///
  /// 但「缓冲空了」不等于「源废了」：弱网下抖个几百毫秒是常态，一律零延迟切源
  /// 会把本来能自愈的源白白换掉。所以留一个很短的观察窗，窗内缓冲恢复就当没发生。
  ///
  /// 之所以不是 const：单测要注入更短的时长。
  static Duration freezeGraceTimeout = const Duration(seconds: 2);

  /// 缓冲中断的观察窗计时器（null = 当前没在等缓冲恢复）
  Timer? _freezeGraceTimer;

  /// 起播阶段「缓冲毫无进展」的上限
  ///
  /// 看门狗是纯计时，只能等满 12 秒。但大部分起播失败其实是**半开连接**：
  /// TCP 连得上，服务端一个字节都不给，ffmpeg 的默认读写超时是无限等待。
  /// 这种情况下播放器确实处在缓冲中，只是缓冲进度一动不动。
  ///
  /// 于是换个判据——不看墙钟，看**有没有数据在进**：
  /// 只要 [FijkPlayer.onBufferPosUpdate] 还在推，说明源是活的，慢一点也给它机会；
  /// 一旦连续这么久没有任何缓冲进展，基本可以断定这个源拿不到数据。
  ///
  /// 之所以不是 const：单测要注入更短的时长。
  static Duration startStallTimeout = const Duration(seconds: 4);

  /// 起播缓冲停滞计时器（null = 当前不在起播缓冲中）
  Timer? _stallTimer;

  /// 缓冲状态订阅，dispose 时必须取消
  StreamSubscription<bool>? _bufferSub;

  /// 缓冲进度订阅，dispose 时必须取消
  StreamSubscription<Duration>? _bufferPosSub;

  /// 切源锁，防止 error 和 freeze 同时触发
  bool isSwitching = false;

  /// 是否已释放
  bool _disposed = false;

  /// 硬解是否失败过，需要回退到软解
  ///
  /// 注意：这个标志必须与 mediacodec 选项**双向同步**，
  /// 每次播放都要显式下发 `_hwDecodeFailed ? 0 : 1`。
  /// 早期版本只在失败时写 0、从来没人写回 1，导致一次误判
  /// （例如某个源返回 404）就让整个会话一直跑 CPU 软解，直到重启 App。
  bool _hwDecodeFailed = false;

  /// 连续"还没渲染出画面就失败"的次数，达到阈值才判定为硬解失败
  static const int _hwFailThreshold = 2;
  int _hwDecodeErrorStreak = 0;

  /// 本次播放是否已经渲染出画面。
  /// 用于区分「解码失败」与「网络类错误（404 / DNS / 断网）」：
  /// 渲染成功过之后再出错，基本可以排除解码问题。
  bool _rendered = false;

  /// 初始化播放器（注册监听器）
  void initPlayer({
    VoidCallback? onFreeze,
    VoidCallback? onError,
  }) {
    _onFreezeCallback = onFreeze;
    _onErrorCallback = onError;
    _disposed = false;

    player.addListener(_playerValueListener);
    _bufferSub?.cancel();
    _bufferSub = player.onBufferStateUpdate.listen(_onBufferState);
    _bufferPosSub?.cancel();
    _bufferPosSub = player.onBufferPosUpdate.listen(_onBufferPos);
  }

  bool _optionsInitialized = false;

  /// 上一次下发到原生的 mediacodec 取值（null 表示尚未下发 / 已失效）
  int? _lastMediacodec;

  /// 上一次下发的音量 / 请求头，值不变时跳过这次 platform 往返
  double? _lastVolume;
  String? _lastReferer;
  String? _lastUserAgent;

  /// 切台请求自增序号：快速连按时只让最后一次生效，
  /// 避免旧请求的 await 回来后覆盖新源（表现为"切到 A 台播的是 B 台"）。
  int _playSeq = 0;

  /// 预热播放器，配置一次永久有效的 FFmpeg option
  ///
  /// 所有 option 打包成一个 [FijkOption] 一次性下发，
  /// 原来逐个 setOption 要走 13 次 platform channel 往返。
  Future<void> warmUp() async {
    if (_optionsInitialized) return;
    _optionsInitialized = true;

    try {
      _logger.debug('预热播放器...');

      final opt = FijkOption();
      opt.setHostOption("request-screen-on", 1);

      // 探测参数：原先 probesize 只有 100KB、analyzeduration 0.5s，
      // 为了压起播时间压到比 ffplay 默认低两个量级。副作用是码率偏高、
      //  playlist 较长、或首个 track 不是视频的源，ffmpeg 还没探完 fmt_ctx 就放弃，
      //  典型表现就是「本机 ffplay 能播，App 播不出来」。
      //  这里放宽到与 ffplay 同量级；probesize 只是上限，够用就会提前收，
      //  所以不会真的拖慢换台。
      opt.setFormatOption("analyzeduration", 2000000);
      opt.setFormatOption("probesize", 5 * 1024 * 1024);
      opt.setFormatOption("fflags", "nobuffer");
      opt.setFormatOption("max_delay", "100000");
      opt.setFormatOption("rtsp_transport", "tcp");
      opt.setFormatOption("allowed_media_types", "video");
      // 网络抖动时自动重连
      opt.setFormatOption("reconnect", 1);
      // 输入缓冲上限（字节）。原先 infbuf=1 表示不限制缓冲区，
      // 长时间看直播时内存单调递增，低端电视盒子容易 OOM。
      // 这里恢复 ijk 默认的限制缓冲并与 max-buffer-size 成对使用；
      // 若真机出现频繁缓冲，把 infbuf 改回 1 即可还原原行为。
      opt.setFormatOption("max-buffer-size", 2 * 1024 * 1024);

      // 网络读写超时（微秒）。ffmpeg 的 http/tcp 默认无限等待，半开连接会把
      // prepareAsync 永久拖住。这里先让底层尽力超时，底层不认的情况下
      // 还有 Dart 侧的 [startWatchdogTimeout] 兜底，两层取先到的那个。
      opt.setFormatOption("rw_timeout", 10 * 1000000);
      opt.setFormatOption("timeout", 10 * 1000000);

      opt.setPlayerOption("packet-buffering", 0);
      opt.setPlayerOption("infbuf", 0);
      opt.setPlayerOption("framedrop", 5);
      opt.setPlayerOption("mediacodec", 1);
      opt.setPlayerOption("mediacodec-auto-rotate", 1);
      opt.setPlayerOption("mediacodec-handle-resolution-change", 1);
      opt.setPlayerOption("mediacodec-hevc", 1);
      // 全局打开自动起播：setDataSource 之后直接 prepareAsync 即可，
      // 省掉 setDataSource(autoPlay: true) 内部额外的 setOption + start 两次 await。
      opt.setPlayerOption("start-on-prepared", 1);
      // 注意：不要关掉 enable-position-notify（插件在 Java 层默认开启）。
      // Dart 侧的 player.currentPos 依赖 EventChannel 'pos' 事件更新，
      // 关掉通知后 currentPos 恒为 0，卡顿检测会持续误判并疯狂切源。

      await player.applyOptions(opt);

      _lastMediacodec = 1;
      _hwDecodeFailed = false;
      _hwDecodeErrorStreak = 0;
      _logger.debug('预热播放器完成');
    } catch (e) {
      _optionsInitialized = false;
      _lastMediacodec = null;
      _logger.debug('预热播放器失败: $e');
    }
  }

  /// 本次播放的直播源地址
  ///
  /// 供源健康度记录使用。两点考量：
  /// - 回看传进来的是带 playseek 的录像地址，不是直播源，播失败也不代表这个
  ///   频道不可用，所以回看时置空，健康度直接跳过（[SourceHealthUtil] 里
  ///   对空串直接 return）。
  /// - 播放器回调是异步的，靠这个字段取"最近一次起播的源"。每次起播都会先
  ///   reset player，旧播放的回调不会再到达，所以单个字段就够，不必按 seq 存。
  String currentUrl = '';

  int _playTimestamp = 0;

  /// 每次播放前下发 mediacodec，取值未变化时跳过
  Future<void> _applyDecodeOptions() async {
    final value = _hwDecodeFailed ? 0 : 1;
    if (_lastMediacodec == value) return;
    await player.setOption(FijkOption.playerCategory, "mediacodec", value);
    _lastMediacodec = value;
    if (_hwDecodeFailed) _logger.warning("硬解失败，本次回退到软解");
  }

  /// 音量未变化时不重复下发
  Future<void> _ensureVolume(double volume) async {
    if (_lastVolume == volume) return;
    try {
      await player.setVolume(volume);
      _lastVolume = volume;
    } catch (_) {
      // setVolume 失败不影响播放
    }
  }

  /// 请求头（referer / user_agent）未变化时不重复下发
  Future<void> _ensureHeaders(Iptv iptv) async {
    final referer = iptv.url.contains('xuexi.cn') ? 'https://www.xuexi.cn/' : '';
    const userAgent = 'Mozilla/5.0';

    final futures = <Future<void>>[];
    if (_lastReferer != referer) {
      futures.add(player.setOption(FijkOption.formatCategory, "referer", referer));
      _lastReferer = referer;
    }
    if (_lastUserAgent != userAgent) {
      futures.add(player.setOption(FijkOption.formatCategory, "user_agent", userAgent));
      _lastUserAgent = userAgent;
    }
    if (futures.isNotEmpty) await Future.wait(futures);
  }

  /// 播放直播源
  ///
  /// 起播选源不再是"永远取第一条"，而是取健康度最好的一条
  /// （[SourceHealthUtil.pickBest]），失败过的源会被排到后面。
  @action
  Future<void> playIptv(Iptv iptv) async {
    await _startPlay(iptv, SourceHealthUtil.pickBest(iptv.url), playback: false);
  }

  /// 播放某段节目的回看录像
  ///
  /// [url] 由 [CatchupUtil.buildUrls] 生成。与直播的差别：内容是有限长度的录像
  /// （有明确时长），播到结尾会收到 completed，由 [onPlaybackEnd] 交给上层处理。
  Future<void> playCatchup(Iptv source, {required String url}) async {
    await runInAction(() async {
      await _startPlay(source, url, playback: true);
    });
  }

  /// 当前是否在播放回看录像
  bool isPlayback = false;

  /// 回看录像播完时的回调
  ///
  /// 通过 initPlayer 传入，不设为 observable 以避免重新生成 MobX 代码。
  VoidCallback? onPlaybackEnd;

  Future<void> _startPlay(Iptv iptv, String url, {required bool playback}) async {
    final seq = ++_playSeq;
    _playTimestamp = DateTime.now().millisecondsSinceEpoch;
    _rendered = false;
    isPlayback = playback;
    currentUrl = playback ? '' : url;

    try {
      _logger.debug(playback ? '播放回看: $url' : '播放直播源: $iptv');
      _freezeTimer?.cancel();
      // 上一次的缓冲观察窗作废：新源起播本来就要缓冲，不该被旧账判死
      _cancelFreezeGrace();
      _cancelStall();
      state = PlayerState.waiting;
      // 从这里开始计时：后面任何一步卡住都会由看门狗兜住
      _startWatchdog(seq);

      // 兜底：重建播放器或首次预热失败时补一次
      if (!_optionsInitialized) await warmUp();

      if (player.state != FijkState.idle) {
        await player.reset();
        // 原生 reset 不保证保留已下发的 option，缓存作废以便重新下发
        _lastMediacodec = null;
        _lastReferer = null;
        _lastUserAgent = null;
      }
      if (seq != _playSeq) return;

      await _applyDecodeOptions();
      await _ensureVolume(1.0);
      await _ensureHeaders(iptv);
      if (seq != _playSeq) return;

      // 不用 autoPlay: true —— 它会额外 setOption(start-on-prepared) 再 start()，
      // 而全局已经把这个开关打开，直接 prepareAsync 就好。
      await player.setDataSource(url);
      if (seq != _playSeq) return;
      await player.prepareAsync();
      if (seq != _playSeq) return;

      state = PlayerState.playing;
      // 竞态兜底：prepared 事件若提前到达（那时 state 还是 waiting），
      // 监听器不会启动卡顿检测，这里补一次。
      if (player.state == FijkState.prepared) {
        _cancelWatchdog();
        _startFreezeCheck();
      }
      // 其余情况（多数是 asyncPreparing）交给看门狗盯住：
      // 既不到 prepared 也不报错时，只有它会把这次起播判死。
    } catch (e) {
      _logger.warning(playback ? "回看播放失败: $e" : "切台失败: $e");
      if (!_disposed && seq == _playSeq) {
        // setDataSource / prepareAsync 直接抛错时，native 不会给出任何状态回调，
        // 界面会干等在 waiting 上。这里主动驱动上层切源，别让这次失败石沉大海。
        _cancelWatchdog();
        SourceHealthUtil.recordFailure(currentUrl);
        _onErrorCallback?.call();
      }
    }
  }

  /// 本次是否已经跑到"能出画面"的状态，用于判断起播成功与否
  bool get _reachedPicture =>
      player.state == FijkState.prepared ||
      player.state == FijkState.started ||
      player.value.videoRenderStart;

  /// 启动起播看门狗
  ///
  /// [seq] 用于作废过期的切台请求：连按时旧请求的定时器不能去切新电台的源。
  void _startWatchdog(int seq) {
    _watchdogTimer?.cancel();
    _watchdogTimer = Timer(startWatchdogTimeout, () {
      _watchdogTimer = null;
      if (_disposed || seq != _playSeq) return;
      if (_reachedPicture) return;

      _logger.warning(
          '起播超时 ${startWatchdogTimeout.inSeconds}s 仍未出画面，判定该源不可用');
      _freezeTimer?.cancel();
      // 卡在 asyncPreparing 不上不下，native 不会给 error 回调，这里主动记一次
      SourceHealthUtil.recordFailure(currentUrl);
      // 与卡顿/错误走同一条出口：上层据此切下一个备用源
      _onErrorCallback?.call();
    });
  }

  void _cancelWatchdog() {
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
  }

  /// 重新初始化播放器（释放后重建）
  Future<void> reinitPlayer() async {
    if (!_disposed) return;
    _disposed = false;

    player = FijkPlayer();
    player.addListener(_playerValueListener);
    // 新的 FijkPlayer 实例，旧的缓冲订阅收不到它的事件，必须重新挂
    _bufferSub?.cancel();
    _bufferSub = player.onBufferStateUpdate.listen(_onBufferState);
    _bufferPosSub?.cancel();
    _bufferPosSub = player.onBufferPosUpdate.listen(_onBufferPos);
    _optionsInitialized = false;
    // 新实例不带任何已下发的 option，本地缓存一并作废
    _lastMediacodec = null;
    _lastVolume = null;
    _lastReferer = null;
    _lastUserAgent = null;
    _hwDecodeErrorStreak = 0;
    _rendered = false;
    // 让还挂着的切台请求失效
    _playSeq++;
    await warmUp();
  }

  /// 播放器事件监听
  void _playerValueListener() {
    final st = player.state;

    // 画面已经渲染出来，说明解码链路可用：撤销此前的硬解降级
    if (!_rendered && player.value.videoRenderStart) {
      _rendered = true;
      if (_hwDecodeFailed || _hwDecodeErrorStreak > 0) {
        _hwDecodeFailed = false;
        _hwDecodeErrorStreak = 0;
        _logger.debug('解码正常，恢复硬解');
      }
      // 画面已经出来就说明这次起播成功了
      _cancelWatchdog();
      // 起播停滞计时到此为止：都出画面了，缓冲再慢也不算失败
      _cancelStall();
      // 抹掉这条源的失败记录：冷却期过后重试成功的源也算恢复
      SourceHealthUtil.recordSuccess(currentUrl);
    }

    if (st == FijkState.error) {
      _logger.warning("播放错误");
      _cancelWatchdog();
      _freezeTimer?.cancel();
      // 网络类错误（404 / DNS / 断网）同样走到这里，过去只要出现 error
      // 就把硬解降级且再也不恢复 —— 一次误判就让整场直播都跑 CPU 软解。
      // 只有"还没渲染出画面"才可能是解码问题，并要求连续多次才降级。
      if (!isSwitching && !_rendered) {
        _hwDecodeErrorStreak++;
        if (_hwDecodeErrorStreak >= _hwFailThreshold && !_hwDecodeFailed) {
          _hwDecodeFailed = true;
          _logger.warning("连续 $_hwDecodeErrorStreak 次未能渲染出画面，判定硬解不可用");
        }
      }
      // 起播失败与播到一半断流都记一次：前者说明源不可用，后者说明源不稳定。
      // 断网时确实会把整批源都记上，但冷却期一过就会重新给机会，
      // 且一旦播放成功立即清除记录，误伤可控。
      SourceHealthUtil.recordFailure(currentUrl);
      _onErrorCallback?.call();
    }
    else if (st == FijkState.completed) {
      // 录像播完：直播永远不会走到这里，所以只在回看时有意义
      _cancelWatchdog();
      _freezeTimer?.cancel();
      if (isPlayback) {
        _logger.debug('回看播放结束');
        onPlaybackEnd?.call();
      }
    }
    else if (st == FijkState.prepared && state == PlayerState.playing) {
      isSwitching = false;
      _cancelWatchdog();
      if (_playTimestamp > 0) {
        _logger.debug('${isPlayback ? '回看' : '播放器'}就绪耗时: ${DateTime.now().millisecondsSinceEpoch - _playTimestamp}ms');
        _playTimestamp = 0;
      }
      _startFreezeCheck();
    }

    // started 同样说明起播完成（start-on-prepared 已全局打开，
    // prepared 可能一闪而过，这里再兜一道）
    if (st == FijkState.started) _cancelWatchdog();

    final newSize = player.value.size ?? Size.zero;

    // 检查尺寸是否有效且与当前存储的值不同
    if (newSize.width > 0 && newSize.height > 0 && newSize != resolution) {
      // 必须在 runInAction 中更新 MobX 状态
      runInAction(() {
        resolution = newSize;
        aspectRatio=newSize.aspectRatio;
      });
    }
  }

  /// 检测间隔
  static const Duration _freezeCheckInterval = Duration(seconds: 5);

  /// 首帧宽限轮次
  ///
  /// prepared 之后 ffmpeg 还要等到第一个 I 帧才会渲染，弱网、高码率、
  /// GOP 长的源超过 5 秒才出画面是很常见的事。原来第一次检查（5s）就直接判死，
  /// 结果是把用户「本机 ffplay 明明能播」的源活活切走，还反复重来。
  /// 这里放宽一轮：第二次检查（约 10s）仍无画面才判定卡顿。
  static const int _firstFrameGraceChecks = 1;

  /// 启动卡顿检测
  ///
  /// 「播到一半卡住」的主判定已经交给 [_onBufferState]：native 主动推缓冲事件，
  /// 只需等 [freezeGraceTimeout] 就能下结论。这里保留的是兜底——
  /// 缓冲事件没送到、或者流不动但缓冲区并未见底的情况下，靠采样播放位置再发现一次。
  void _startFreezeCheck() {
    _freezeTimer?.cancel();
    Duration? _lastPosition;
    int _checkCount = 0;
    _freezeTimer = Timer.periodic(_freezeCheckInterval, (timer) {
      // 播放器已释放，停掉检测避免空转
      if (_disposed) {
        timer.cancel();
        return;
      }

      // currentPos 是同步 getter（由 EventChannel 的 'pos' 事件更新），无需 await
      final pos = player.currentPos;
      // videoRenderStart 同样是 bool，await 它只会白跑一个 microtask
      final videoRendered = player.value.videoRenderStart;
      if (videoRendered) _rendered = true;

      // 首帧检测：宽限期内只记录，不判死
      if (!videoRendered) {
        if (_checkCount < _firstFrameGraceChecks) {
          _checkCount++;
          return;
        }
        _logger.warning("${_freezeCheckInterval.inSeconds * (_checkCount + 1)}s 内未渲染出画面，判定为卡顿");
        _onFreezeCallback?.call();
        timer.cancel();
        return;
      }

      // 后续检测：播放位置不再前进
      if (_lastPosition != null && pos == _lastPosition) {
        _logger.warning("检测到播放卡顿");
        _onFreezeCallback?.call();
        timer.cancel();
        return;
      }

      _lastPosition = pos;
      _checkCount++;
    });
  }

  /// 缓冲状态变化（native 主动推，比轮询快得多）
  ///
  /// ijkplayer 在 `BUFFERING_START` / `BUFFERING_END` 时通过 EventChannel 推 `freeze`
  /// 事件，fijkplayer 转成这里的 [FijkPlayer.onBufferStateUpdate]。
  /// 这是**播放器自己知道缓冲空了**，不需要靠采样播放位置去猜。
  ///
  /// 起播阶段必然处于缓冲中（第一帧还没解出来），那段时间一律不插手，
  /// 交给 [startWatchdogTimeout] 的看门狗——否则每换一次源都要被误判一次卡顿。
  void _onBufferState(bool buffering) {
    if (!buffering) {
      // 缓冲恢复了，这次抖动不算数
      _freezeGraceTimer?.cancel();
      _freezeGraceTimer = null;
      _cancelStall();
      return;
    }

    // 还没出过画面：是起播，不是卡顿。
    // 但"缓冲中却毫无进展"正是半开连接的特征，交给停滞计时器盯着，
    // 不按卡顿的宽限窗口处理——否则每换一次源都要误杀一次。
    if (!_rendered) {
      _armStallTimer();
      return;
    }
    // 已经在等了，不要重复起表
    if (_freezeGraceTimer != null) return;

    _freezeGraceTimer = Timer(freezeGraceTimeout, () {
      _freezeGraceTimer = null;
      if (_disposed || isSwitching) return;

      _logger.warning(
          '缓冲中断 ${freezeGraceTimeout.inSeconds}s 未恢复，判定卡顿');
      // 停掉轮询，避免同一件事触发两次切源
      _freezeTimer?.cancel();
      _freezeTimer = null;
      // 与起播超时、native 报错走同一条出口
      _onFreezeCallback?.call();
    });
  }

  /// 取消缓冲观察窗
  void _cancelFreezeGrace() {
    _freezeGraceTimer?.cancel();
    _freezeGraceTimer = null;
  }

  /// 起播缓冲要重新计时：还处在缓冲中就得继续盯，出画面了就收工
  void _armStallTimer() {
    _stallTimer?.cancel();
    _stallTimer = Timer(startStallTimeout, () {
      _stallTimer = null;
      // 期间出过画面就说明起播成功了，别再判死
      if (_disposed || isSwitching || _rendered) return;

      _logger.warning(
          '起播缓冲 ${startStallTimeout.inSeconds}s 无任何进展，判定该源不可达');
      _cancelWatchdog();
      _freezeTimer?.cancel();
      _freezeTimer = null;
      // 拿不到数据就是源不可用，与起播超时同级
      SourceHealthUtil.recordFailure(currentUrl);
      _onErrorCallback?.call();
    });
  }

  /// 取消起播停滞计时
  void _cancelStall() {
    _stallTimer?.cancel();
    _stallTimer = null;
  }

  /// 缓冲进度更新：数据在进，说明源是活的，重新给一轮时间
  void _onBufferPos(Duration _) {
    if (_stallTimer == null) return;
    _cancelStall();
    // 还在起播缓冲中就继续盯下一轮
    if (!_rendered && player.isBuffering) _armStallTimer();
  }

  /// 释放播放器（统一入口）
  @action
  Future<void> disposePlayer() async {
    if (_disposed) return;
    _disposed = true;
    // 让还在 await 的切台请求失效，避免释放后继续往原生写入
    _playSeq++;

    try {
      _logger.debug("释放播放器资源...");
      _freezeTimer?.cancel();
      _freezeTimer = null;
      _cancelWatchdog();
      _cancelFreezeGrace();
      _cancelStall();
      _bufferSub?.cancel();
      _bufferSub = null;
      _bufferPosSub?.cancel();
      _bufferPosSub = null;

      player.removeListener(_playerValueListener);

      // 停止播放并释放资源
      try {
        await player.setVolume(0.0);
        _lastVolume = 0.0;
      } catch (_) {}
      if (player.state != FijkState.idle) {
        await player.stop();
      }
      await player.release(); // 异步释放底层资源

      // 原生实例已销毁，option 缓存全部作废
      _lastMediacodec = null;
      _lastReferer = null;
      _lastUserAgent = null;
      _rendered = false;
      currentUrl = '';

      // 重置状态
      state = PlayerState.waiting;
      aspectRatio = null;
      resolution = Size.zero;
      isSwitching = false;
      isPlayback = false;

      _logger.debug("播放器资源释放成功");
    } catch (e) {
      _logger.error("释放播放器失败: $e");
    }
  }
}
