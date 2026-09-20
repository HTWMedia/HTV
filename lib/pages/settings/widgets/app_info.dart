import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// 更新按钮的焦点节点。
  ///
  /// 原来这里只有一个 GestureDetector，没有 Focus，遥控器用户永远够不到它——
  /// 有更新时也只能靠鼠标点。现在它是设置页焦点链上的一个节点：
  /// 在设置主列表的第一项按「上」就会遍历到这里，再按「下」回到列表。
  final _updateButtonFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _checkUpdate();
  }

  @override
  void dispose() {
    _updateButtonFocusNode.dispose();
    super.dispose();
  }

  Future<void> _checkUpdate() async {
    await updateStore.loadCurrentVersion();
    await updateStore.refreshLatestRelease();
  }

  /// 聚焦态 + 点击 + OK/回车皆可触发的更新按钮
  Widget _buildUpdateButton() {
    return Focus(
      focusNode: _updateButtonFocusNode,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        switch (event.logicalKey) {
          case LogicalKeyboardKey.select:
          case LogicalKeyboardKey.enter:
          case LogicalKeyboardKey.space:
            updateStore.downloadAndInstall();
            return KeyEventResult.handled;
          default:
            return KeyEventResult.ignored;
        }
      },
      child: GestureDetector(
        onTap: () {
          _updateButtonFocusNode.requestFocus();
          updateStore.downloadAndInstall();
        },
        // FocusNode 是 Listenable 而非 ValueListenable，焦点变化时这里会被通知
        child: ListenableBuilder(
          listenable: _updateButtonFocusNode,
          builder: (context, _) {
            final focused = _updateButtonFocusNode.hasFocus;
            return Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
              decoration: BoxDecoration(
                color: Colors.green,
                borderRadius: BorderRadius.circular(8).r,
                // 遥控器用户看不出焦点在哪儿，给一个明确的描边
                border: focused ? Border.all(color: Colors.white, width: 3.w) : null,
              ),
              child: Text(
                '下载更新',
                style: AppTheme.text(Colors.white, 24.sp),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fg = AppTheme.fg(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Observer(
          builder: (_) => Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                'HTV',
                style: AppTheme.text(fg, 60.sp, weight: FontWeight.bold),
              ),
              SizedBox(width: 20.w),
              Text(
                'v${updateStore.currentVersion}',
                style: AppTheme.text(AppTheme.fgFaded(context, AppTheme.oSecondary), 30.sp, weight: FontWeight.bold),
              ),
              SizedBox(width: 20.w),
              if (updateStore.updating)
                Text(
                  updateStore.downloadProgress.isNotEmpty ? updateStore.downloadProgress : '检查中...',
                  style: AppTheme.text(AppTheme.fgFaded(context, AppTheme.oTertiary), 24.sp),
                )
              else if (updateStore.hasUpdate)
                _buildUpdateButton()
              else if (updateStore.latestRelease.tagName != 'v0.0.0')
                Text(
                  '已是最新',
                  style: AppTheme.text(AppTheme.fgFaded(context, AppTheme.oSubtle), 24.sp),
                ),
            ],
          ),
        ),
        Text(
          'https://github.com/HTWMedia/HTV',
          style: AppTheme.text(AppTheme.fgFaded(context, AppTheme.oSecondary), 30.sp),
        ),
      ],
    );
  }
}
