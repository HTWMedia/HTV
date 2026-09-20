import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class SwipeGestureDetector extends StatefulWidget {
  const SwipeGestureDetector({
    super.key,
    required this.child,
    this.onSwipeUp,
    this.onSwipeDown,
    this.onSwipeLeft,
    this.onSwipeRight,
  });

  final Widget child;
  final void Function()? onSwipeUp;
  final void Function()? onSwipeDown;
  final void Function()? onSwipeLeft;
  final void Function()? onSwipeRight;

  @override
  State<SwipeGestureDetector> createState() => _SwipeGestureDetectorState();
}

class _SwipeGestureDetectorState extends State<SwipeGestureDetector> {
  late VelocityTracker _verticalTracker;
  late VelocityTracker _horizontalTracker;

  static const _swipeThreshold = 500;

  @override
  void initState() {
    super.initState();
    _verticalTracker = VelocityTracker.withKind(PointerDeviceKind.touch);
    _horizontalTracker = VelocityTracker.withKind(PointerDeviceKind.touch);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: (details) {
        _verticalTracker = VelocityTracker.withKind(PointerDeviceKind.touch);
        if (details.sourceTimeStamp != null) {
          _verticalTracker.addPosition(details.sourceTimeStamp!, details.globalPosition);
        }
      },
      onVerticalDragUpdate: (details) {
        if (details.sourceTimeStamp != null) {
          _verticalTracker.addPosition(details.sourceTimeStamp!, details.globalPosition);
        }
      },
      onVerticalDragEnd: (details) {
        final velocity = _verticalTracker.getVelocity().pixelsPerSecond.dy;
        if (velocity > _swipeThreshold) {
          widget.onSwipeDown?.call();
        } else if (velocity < -_swipeThreshold) {
          widget.onSwipeUp?.call();
        }
      },
      onHorizontalDragStart: (details) {
        _horizontalTracker = VelocityTracker.withKind(PointerDeviceKind.touch);
        if (details.sourceTimeStamp != null) {
          _horizontalTracker.addPosition(details.sourceTimeStamp!, details.globalPosition);
        }
      },
      onHorizontalDragUpdate: (details) {
        if (details.sourceTimeStamp != null) {
          _horizontalTracker.addPosition(details.sourceTimeStamp!, details.globalPosition);
        }
      },
      onHorizontalDragEnd: (details) {
        final velocity = _horizontalTracker.getVelocity().pixelsPerSecond.dx;
        if (velocity > _swipeThreshold) {
          widget.onSwipeLeft?.call();
        } else if (velocity < -_swipeThreshold) {
          widget.onSwipeRight?.call();
        }
      },
      child: widget.child,
    );
  }
}
