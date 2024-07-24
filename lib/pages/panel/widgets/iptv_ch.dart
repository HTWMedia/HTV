import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class PanelIptvChannel extends StatelessWidget {
  const PanelIptvChannel(this.channel, {super.key});

  final String channel;

  @override
  Widget build(BuildContext context) {
    return Text(
      channel,
      style: TextStyle(
        color: Theme.of(context).colorScheme.onBackground,
        fontSize: 90.sp,
        height: 1,
          decoration: TextDecoration.none
      ),
    );
  }
}
