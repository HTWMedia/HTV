import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import '../stores/player.dart';
import '../utils/logger.dart';

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

  Future<void> _exitApp(BuildContext context) async {
    try {
      final playerStore = GetIt.I<PlayerStore>();
      await playerStore.disposePlayer(); // 彻底释放播放器
    } catch (e) {
      LoggerUtil.error("退出前释放播放器失败: $e");
    }

    SystemNavigator.pop(); // 退出应用
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) {
        if (didPop) return;

        final now = DateTime.now();
        if (_lastPressedAt == null ||
            now.difference(_lastPressedAt!) > const Duration(seconds: 1)) {
          _lastPressedAt = now;

          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('再按一次退出'),
              duration: Duration(seconds: 1),
            ),
          );
          return;
        }

        _exitApp(context);
      },
      child: widget.child,
    );
  }
}
