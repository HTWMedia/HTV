import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get_it/get_it.dart';
import 'package:video_player_example/common/index.dart';

class SettingsAppInfo extends StatefulWidget {
  const SettingsAppInfo({super.key});

  @override
  State<SettingsAppInfo> createState() => _SettingsAppInfoState();
}

class _SettingsAppInfoState extends State<SettingsAppInfo> {
  final updateStore = GetIt.I<UpdateStore>();

  var _version = '';

  _initData() async {
    //final packageInfo = await PackageInfo.fromPlatform();
    setState(() {
      _version = '1.0.0';
    });
  }

  @override
  void initState() {
    super.initState();
    _initData();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              'HTV',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onBackground,
                fontSize: 60.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(width: 20.w),
            Observer(
              builder: (_) => Text(
                'v${updateStore.currentVersion}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onBackground.withOpacity(0.8),
                  fontSize: 30.sp,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        Text(
          'https://github.com/HTWMedia/HTV',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onBackground.withOpacity(0.8),
            fontSize: 30.sp,
          ),
        ),
      ],
    );
  }
}
