import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player_example/common/index.dart';
import 'package:video_player_example/pages/settings/widgets/app_info.dart';
import 'package:video_player_example/pages/settings/widgets/settings.dart';
import 'package:get_it/get_it.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final playerStore = GetIt.I<PlayerStore>();
  final iptvStore = GetIt.I<IptvStore>();
  final updateStore = GetIt.I<UpdateStore>();

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Padding(
            padding: const EdgeInsets.only(left: 40).r,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsAppInfo(),
                SizedBox(height: 30.h),
                const SettingsMain(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}