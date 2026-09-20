import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:video_player_example/common/index.dart';

class PanelTime extends StatefulWidget {
  const PanelTime({super.key});

  @override
  State<PanelTime> createState() => _PanelTimeState();
}

class _PanelTimeState extends State<PanelTime> {
  // 提为静态常量：原来每次 build（每秒一次）都要重新构造两个 DateFormat，
  // 而格式化模式 allocations + locale 数据加载是很贵的部分。
  static final _dateFormat = DateFormat('MM月dd日   E', 'zh-CN');
  static final _timeFormat = DateFormat('HH:mm:ss');

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
    final fg = AppTheme.fg(context);

    return Column(
      children: [
        Text(
          _dateFormat.format(_now),
          style: AppTheme.text(fg, 20.sp),
        ),
        Text(
          _timeFormat.format(_now),
          style: AppTheme.text(fg, 40.sp, weight: FontWeight.bold),
        ),
      ],
    );
  }
}
