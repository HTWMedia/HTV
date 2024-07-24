import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

class PanelTime extends StatefulWidget {
  const PanelTime({super.key});

  @override
  State<PanelTime> createState() => _PanelTimeState();
}

class _PanelTimeState extends State<PanelTime> {
  var _now = DateTime.now();
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  void _initData() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _now = DateTime.now();
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          DateFormat('MM月dd日   E', 'zh-CN').format(_now),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onBackground,
            fontSize: 20.sp,
            decoration: TextDecoration.none,
          ),
        ),
        Text(
          DateFormat('HH:mm:ss').format(_now),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onBackground,
            fontWeight: FontWeight.bold,
            fontSize: 40.sp,
            decoration: TextDecoration.none,
          ),
        ),
      ],
    );
  }
}
