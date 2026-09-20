import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player_example/common/index.dart';

class PanelIptvChannel extends StatelessWidget {
  const PanelIptvChannel(this.channel, {super.key});

  final String channel;

  @override
  Widget build(BuildContext context) {
    return Text(
      channel,
      style: AppTheme.text(AppTheme.fg(context), 90.sp, height: 1),
    );
  }
}
