import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class DelayRenderer extends StatefulWidget {
  const DelayRenderer({super.key, required this.child});

  final Widget child;

  @override
  State<DelayRenderer> createState() => _DelayRendererState();

  /// 待延迟派发的回调队列。
  ///
  /// 每帧只出队一个：一次性 build 上百个子控件会把帧预算打爆，
  /// 摊到多帧才能让列表首屏不被卡住。
  static final _queue = <void Function()>[];

  /// 是否已经排了下一帧。
  ///
  /// 用来实现「队列排空就停机」——原来无条件每帧 addPostFrameCallback，
  /// 即使队列永远是空的也会把自己挂到每一帧上，开机后永不休眠。
  static bool _pumping = false;

  static void enqueue(void Function() fn) {
    _queue.add(fn);
    _requestPump();
  }

  static void remove(void Function() fn) => _queue.remove(fn);

  static void _requestPump() {
    if (_pumping) return;
    _pumping = true;
    SchedulerBinding.instance.addPostFrameCallback((_) => _pump());
  }

  static void _pump() {
    if (_queue.isNotEmpty) _queue.removeAt(0)();

    if (_queue.isNotEmpty) {
      SchedulerBinding.instance.addPostFrameCallback((_) => _pump());
    } else {
      // 排空就停机，下次入队时由 enqueue 重新唤醒，不再每帧空转
      _pumping = false;
    }
  }
}

class _DelayRendererState extends State<DelayRenderer> {
  @override
  void initState() {
    super.initState();
    DelayRenderer._requestPump();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class DelayRendererWidget extends StatefulWidget {
  const DelayRendererWidget({
    super.key,
    required this.child,
    required this.enable,
    this.placeholder,
  });

  final Widget child;
  final bool enable;
  final Widget? placeholder;

  @override
  State<DelayRendererWidget> createState() => _DelayRendererWidgetState();
}

class _DelayRendererWidgetState extends State<DelayRendererWidget> {
  late var _visible = !widget.enable;

  void _notify() {
    if (mounted) setState(() => _visible = true);
  }

  @override
  void initState() {
    super.initState();
    if (widget.enable) DelayRenderer.enqueue(_notify);
  }

  @override
  void dispose() {
    if (widget.enable) DelayRenderer.remove(_notify);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _visible ? widget.child : (widget.placeholder ?? const SizedBox.shrink());
  }
}

extension DelayRendererExtension on Widget {
  Widget delayed({bool enable = true, Widget? placeholder}) {
    return DelayRendererWidget(
      enable: enable,
      placeholder: placeholder,
      child: this,
    );
  }
}

extension DelayRendererListExtension on List<Widget> {
  List<Widget> delayed({bool enable = true, List<Widget?>? placeholder}) {
    return indexed
        .map((it) => (it.$2).delayed(
      enable: enable,
      placeholder: placeholder?.elementAt(it.$1),
    ))
        .toList();
  }
}