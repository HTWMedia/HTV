import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class SwipeGestureDetector extends StatelessWidget {
  SwipeGestureDetector({
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

  final _verticalTracker = VelocityTracker.withKind(PointerDeviceKind.touch);
  final _horizontalTracker = VelocityTracker.withKind(PointerDeviceKind.touch);

  final _swipeThreshold = 100;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragStart: (details) {
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
        if (_verticalTracker.getVelocity().pixelsPerSecond.dy > _swipeThreshold) {
          onSwipeDown?.call();
        } else if (_verticalTracker.getVelocity().pixelsPerSecond.dy < -_swipeThreshold) {
          onSwipeUp?.call();
        }
      },
      onHorizontalDragStart: (details) {
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
        if (_horizontalTracker.getVelocity().pixelsPerSecond.dx > _swipeThreshold) {
          onSwipeLeft?.call();
        } else if (_horizontalTracker.getVelocity().pixelsPerSecond.dx < -_swipeThreshold) {
          onSwipeRight?.call();
        }
      },
      child: child,
    );
  }
}
