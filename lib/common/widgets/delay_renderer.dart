import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class DelayRenderer extends StatefulWidget {
  const DelayRenderer({super.key, required this.child});

  final Widget child;

  @override
  State<DelayRenderer> createState() => _DelayRendererState();

  static final _queue = <void Function()>[];
}

class _DelayRendererState extends State<DelayRenderer> {
  Future<void> _dispatch() async {
    if (DelayRenderer._queue.isNotEmpty) {
      DelayRenderer._queue.removeAt(0)();
    }

    SchedulerBinding.instance.addPostFrameCallback((_) => _dispatch());
  }

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addPostFrameCallback((_) => _dispatch());
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
    if (widget.enable) DelayRenderer._queue.add(_notify);
  }

  @override
  void dispose() {
    if (widget.enable) DelayRenderer._queue.remove(_notify);
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