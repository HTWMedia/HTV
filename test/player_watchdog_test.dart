import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fijkplayer_ijkfix/fijkplayer_ijkfix.dart';
import 'package:video_player_example/common/index.dart';

/// 测试用的起播时限（真实计时，不走 fake clock，见下方说明）
const _watchdogTimeout = Duration(milliseconds: 800);

/// 起播时限的业务默认值，tearDown 里还原
const _realWatchdogTimeout = Duration(seconds: 12);

/// 测试用的缓冲宽限（真实计时）
const _freezeGrace = Duration(milliseconds: 500);

/// 缓冲宽限的业务默认值，tearDown 里还原
const _realFreezeGrace = Duration(seconds: 2);

/// 测试用的起播停滞上限（真实计时）
const _stallTimeout = Duration(milliseconds: 500);

/// 起播停滞上限的业务默认值，tearDown 里还原
const _realStallTimeout = Duration(seconds: 4);

/// 伪造 native 侧的 ijkplayer。
///
/// [FijkPlayer] 的状态完全由 EventChannel 推上来的事件驱动，
/// 想要复现「prepareAsync 之后石沉大海」——也就是用户反馈的那个
/// 「进了 App 一直加载、不自动切源」——就得让 method channel 在收到
/// prepareAsync 时把状态推进到 [FijkState.asyncPreparing] 然后彻底闭嘴。
class FakeIjkNative {
  /// true = 起播请求发出后 native 再无任何回应（半开连接）
  bool stuckAfterPrepareAsync = true;

  /// false = prepared 之后迟迟不出画面（弱网 / GOP 长的源）
  bool emitVideoRenderStart = true;

  MockStreamHandlerEventSink? _events;

  EventChannel get _eventChannel =>
      const EventChannel('befovy.com/fijkplayer/event/1');

  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    messenger.setMockMethodCallHandler(
      const MethodChannel('befovy.com/fijk'),
      (call) async => call.method == 'createPlayer' ? 1 : null,
    );
    messenger.setMockStreamHandler(
      _eventChannel,
      // 注意：这里必须用「语块体」——任何 `=> 有值表达式` 的写法都会把表达式的值
      // 当作 'listen' 通道调用的返回值回给 Dart 侧，而赋值表达式的值正是 sink 本身，
      // 会被 StandardMethodCodec 判为 Invalid argument。
      _FakeEventStream((args, events) {
        _events = events;
      }),
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('befovy.com/fijkplayer/1'),
      _handlePlayerCall,
    );
  }

  Future<Object?> _handlePlayerCall(MethodCall call) async {
    switch (call.method) {
      case 'setDataSource':
        // 真实 native 也是这么回报的
        _emitState(FijkState.idle, FijkState.initialized);
        break;
      case 'prepareAsync':
        _emitState(
          FijkState.initialized,
          stuckAfterPrepareAsync
              ? FijkState.asyncPreparing
              : FijkState.prepared,
        );
        if (!stuckAfterPrepareAsync && emitVideoRenderStart) {
          _events?.success({'event': 'rendering_start', 'type': 'video'});
        }
        break;
    }
    await _deliverEvents();
    return null;
  }

  /// 让已经排队的事件先送到 [FijkPlayer]。
  ///
  /// 事件要过 controller → binary messenger → EventChannel 好几跳才落地，
  /// 比这次 method call 自己的返回值晚，而且晚的是**计时器轮次**而非纯微任务：
  /// 在 testWidgets 的 FakeAsync 里它必须等到 pump 才送达，纯 await 微任务帧无效。
  /// 而 _startPlay 是「await setDataSource 之后紧接着 prepareAsync」，
  /// 后者要求 state 已是 initialized，晚一帧就是 StateError。
  /// 所以这些用例用普通 test()（真实计时区），这里再等两个计时轮次把结果钉死。
  Future<void> _deliverEvents() async {
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }

  void _emitState(FijkState oldState, FijkState newState) {
    _events?.success({
      'event': 'state_change',
      'old': oldState.index,
      'new': newState.index,
    });
  }

  /// 推缓冲事件，对应 native 的 BUFFERING_START / BUFFERING_END。
  /// 送达要过好几跳，调用方记得 [deliver] 一下。
  void emitFreeze(bool buffering) {
    _events?.success({'event': 'freeze', 'value': buffering});
  }

  /// 推缓冲进度，对应 native 的 BUFFERING_UPDATE。用来表达"数据在进"。
  void emitBufferPos(int millis) {
    _events?.success({'event': 'buffering', 'head': millis, 'percent': 0});
  }

  Future<void> deliver() => _deliverEvents();
}

typedef _FakeEventStreamListen = void Function(
    Object? arguments, MockStreamHandlerEventSink events);

class _FakeEventStream implements MockStreamHandler {
  _FakeEventStream(this._onListen);

  final _FakeEventStreamListen _onListen;

  @override
  void onListen(Object? arguments, MockStreamHandlerEventSink events) {
    _onListen(arguments, events);
  }

  @override
  void onCancel(Object? arguments) {}
}

Iptv _buildIptv(String url) => Iptv(
      idx: 0,
      channel: 1,
      groupIdx: 0,
      name: '测试频道',
      url: url,
      tvgName: 'test',
    );

void main() {
  late FakeIjkNative native;
  final stores = <PlayerStore>[];

  setUp(() {
    native = FakeIjkNative()..install();
    PlayerStoreBase.startWatchdogTimeout = _watchdogTimeout;
    PlayerStoreBase.freezeGraceTimeout = _freezeGrace;
    PlayerStoreBase.startStallTimeout = _stallTimeout;
  });

  tearDown(() async {
    // 用例失败时也要收干净：残留的 Timer 会跨用例回调到已经作废的对象上
    for (final store in stores) {
      await store.disposePlayer();
    }
    stores.clear();
    PlayerStoreBase.startWatchdogTimeout = _realWatchdogTimeout;
    PlayerStoreBase.freezeGraceTimeout = _realFreezeGrace;
    PlayerStoreBase.startStallTimeout = _realStallTimeout;
  });

  PlayerStore _createStore({required VoidCallback onError, VoidCallback? onFreeze}) {
    final store = PlayerStore();
    store.initPlayer(onError: onError, onFreeze: onFreeze ?? () {});
    stores.add(store);
    return store;
  }

  test('起播超时：native 卡在 asyncPreparing 时必须有人把它判死', () async {
    var errorCount = 0;
    final store = _createStore(onError: () => errorCount++);

    await store.playIptv(_buildIptv('http://127.0.0.1:1/live.m3u8'));

    // 起播刚发出，此时不该有任何判定
    expect(errorCount, 0);

    // 还没到超时
    await Future<void>.delayed(_watchdogTimeout - const Duration(milliseconds: 300));
    expect(errorCount, 0);

    // 超过看门狗时限：上层要收到 error 才会去切下一个备用源
    await Future<void>.delayed(const Duration(milliseconds: 600));
    expect(
      errorCount,
      1,
      reason: 'native 既不 prepared 也不报错时，看门狗是唯一能把这次起播判死的机制',
    );
  });

  test('起播成功：prepared 之后看门狗必须退场，不能误判', () async {
    native.stuckAfterPrepareAsync = false;

    var errorCount = 0;
    final store = _createStore(onError: () => errorCount++);

    await store.playIptv(_buildIptv('http://127.0.0.1:1/live.m3u8'));

    expect(store.state, PlayerState.playing);

    // 远超过看门狗时限之后，也不该冒出额外的 error
    await Future<void>.delayed(_watchdogTimeout * 2 + const Duration(milliseconds: 300));
    expect(errorCount, 0);
  });

  test('播放器已释放后，看门狗到点不再回调', () async {
    var errorCount = 0;
    final store = _createStore(onError: () => errorCount++);

    await store.playIptv(_buildIptv('http://127.0.0.1:1/live.m3u8'));
    await store.disposePlayer();

    await Future<void>.delayed(_watchdogTimeout * 2 + const Duration(milliseconds: 300));
    expect(
      errorCount,
      0,
      reason: '页面已经销毁，再回调会让上层拿着失效的 context 去弹窗 / 切源',
    );
  });

  test('播到一半缓冲中断：宽限一过就切源，不必等轮询攒够两轮', () async {
    // prepared 并且出了画面，模拟"已经正常播起来了"
    native.stuckAfterPrepareAsync = false;

    var freezeCount = 0;
    final store =
        _createStore(onError: () {}, onFreeze: () => freezeCount++);

    await store.playIptv(_buildIptv('http://127.0.0.1:1/live.m3u8'));
    expect(freezeCount, 0);

    // native 主动上报缓冲耗尽
    native.emitFreeze(true);
    await native.deliver();

    // 还没到宽限
    await Future<void>.delayed(_freezeGrace - const Duration(milliseconds: 200));
    expect(freezeCount, 0);

    // 宽限一过立刻判死。旧逻辑靠 5 秒轮询 + 两次采样，这里要等到 10 秒
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(
      freezeCount,
      1,
      reason: '缓冲中断超过 freezeGraceTimeout 就该切源，不等轮询',
    );
  });

  test('缓冲在宽限内恢复：不算卡顿，不能切源', () async {
    native.stuckAfterPrepareAsync = false;

    var freezeCount = 0;
    final store =
        _createStore(onError: () {}, onFreeze: () => freezeCount++);

    await store.playIptv(_buildIptv('http://127.0.0.1:1/live.m3u8'));

    native.emitFreeze(true);
    await native.deliver();
    await Future<void>.delayed(_freezeGrace ~/ 2);
    native.emitFreeze(false);
    await native.deliver();

    // 远超宽限
    await Future<void>.delayed(_freezeGrace * 3);
    expect(
      freezeCount,
      0,
      reason: '弱网抖一下就切源，会把本来能自愈的源白白换掉',
    );
  });

  test('起播阶段的缓冲不算卡顿：还没出画面时不插手', () async {
    // prepared 了但迟迟不出画面，正是"起播必然在缓冲"的状态
    native.stuckAfterPrepareAsync = false;
    native.emitVideoRenderStart = false;
    // 起播看门狗拉长，免得 error 抢在前面把用例搅浑
    PlayerStoreBase.startWatchdogTimeout = const Duration(seconds: 30);

    var freezeCount = 0;
    final store =
        _createStore(onError: () {}, onFreeze: () => freezeCount++);

    await store.playIptv(_buildIptv('http://127.0.0.1:1/live.m3u8'));

    native.emitFreeze(true);
    await native.deliver();

    await Future<void>.delayed(_freezeGrace * 4);
    expect(
      freezeCount,
      0,
      reason: '起播必然在缓冲，这时候判死等于每换一次源就误杀一次',
    );
  });

  test('起播缓冲毫无进展：不等满 12 秒看门狗就判死', () async {
    // prepared 了但迟迟不出画面，且缓冲进度一动不动 —— 半开连接的典型特征：
    // TCP 连得上，服务端一个字节都不给，ffmpeg 默认读写超时是无限等待
    native.stuckAfterPrepareAsync = false;
    native.emitVideoRenderStart = false;
    // 看门狗拉长，确保触发的是停滞判定而不是它
    PlayerStoreBase.startWatchdogTimeout = const Duration(seconds: 30);

    var errorCount = 0;
    final store = _createStore(onError: () => errorCount++);

    await store.playIptv(_buildIptv('http://127.0.0.1:1/live.m3u8'));
    native.emitFreeze(true);
    await native.deliver();
    expect(errorCount, 0);

    // 离看门狗时限还差得远，但已经超过停滞上限
    await Future<void>.delayed(
        _stallTimeout + const Duration(milliseconds: 300));
    expect(
      errorCount,
      1,
      reason: '缓冲一动不动说明根本拿不到数据，不该让用户白等满看门狗',
    );
  });

  test('起播缓冲有进展：慢源要给机会，不能判死', () async {
    native.stuckAfterPrepareAsync = false;
    native.emitVideoRenderStart = false;
    PlayerStoreBase.startWatchdogTimeout = const Duration(seconds: 30);

    var errorCount = 0;
    final store = _createStore(onError: () => errorCount++);

    await store.playIptv(_buildIptv('http://127.0.0.1:1/live.m3u8'));
    native.emitFreeze(true);
    await native.deliver();

    // 每 150ms 来一点缓冲进度，累计时长远超停滞上限
    for (var i = 1; i <= 6; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      native.emitBufferPos(i * 100);
      await native.deliver();
    }

    expect(
      errorCount,
      0,
      reason: '数据在进就说明源是活的，弱网慢源不能因为起播慢被误杀',
    );
  });
}
