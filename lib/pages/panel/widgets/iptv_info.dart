import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:get_it/get_it.dart';
import 'package:video_player_example/common/index.dart';

class PanelIptvInfo extends StatelessWidget {
  PanelIptvInfo({this.epgShowFull = true, super.key});

  late final epgShowFull;

  final iptvStore = GetIt.I<IptvStore>();
  final playerStore = GetIt.I<PlayerStore>();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // 频道名称
            Observer(
              builder: (_) => Text(
                iptvStore.currentIptv.name,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onBackground,
                  fontSize: 60.sp,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none
                ),
              ),
            ),
            SizedBox(width: 40.w),
            // 播放状态
            Observer(
              builder: (_) => Text(
                playerStore.state == PlayerState.failed ? playerStore.errorInfo + '播放失败！' : '',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none
                ),
              ),
            )
          ],
        ),
        // 节目单
        Observer(
          builder: (_) => ConstrainedBox(
            constraints: BoxConstraints(maxWidth: epgShowFull ? 1.sw : 500.w),
            child: Text(
              '正在播放：${iptvStore.currentIptvProgrammes.current.isNotEmpty ? iptvStore.currentIptvProgrammes.current : '无节目'}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onBackground.withOpacity(0.8),
                fontSize: 30.sp,
                  decoration: TextDecoration.none
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        Observer(
          builder: (_) => ConstrainedBox(
            constraints: BoxConstraints(maxWidth: epgShowFull ? 1.sw : 500.w),
            child: Text(
              '稍后播放：${iptvStore.currentIptvProgrammes.next.isNotEmpty ? iptvStore.currentIptvProgrammes.next : '无节目'}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onBackground.withOpacity(0.8),
                fontSize: 30.sp,
                  decoration: TextDecoration.none
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }
}
