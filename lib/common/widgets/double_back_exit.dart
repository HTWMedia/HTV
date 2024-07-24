import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DoubleBackExit extends StatefulWidget {
  final Widget child;

  const DoubleBackExit({super.key, required this.child});

  @override
  State<DoubleBackExit> createState() {
    return DoubleBackExitState();
  }
}

class DoubleBackExitState extends State<DoubleBackExit> {
  DateTime? _lastPressedAt; //上次点击时间

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) {
        if (didPop) {
          return;
        } else {
          if (_lastPressedAt == null || DateTime.now().difference(_lastPressedAt!) > const Duration(seconds: 1)) {
            _lastPressedAt = DateTime.now();

            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('再按一次退出'),
                duration: Duration(seconds: 1),
              ),
            );

            return;
          }

          SystemNavigator.pop();
        }
      },
      child: widget.child,
    );
  }
}
