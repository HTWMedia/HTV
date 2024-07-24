import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get_it/get_it.dart';
import 'package:video_player_example/common/index.dart';

class PanelPlayerInfo extends StatelessWidget {
  PanelPlayerInfo({super.key});

  final playerStore = GetIt.I<PlayerStore>();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Observer(
          builder: (_) => Text(
            '分辨率：${playerStore.resolution.width.toInt()}×${playerStore.resolution.height.toInt()}',
            style: TextStyle(color: Theme.of(context).colorScheme.onBackground, fontSize: 30.sp,decoration: TextDecoration.none),
          ),
        )
      ],
    );
  }
}
