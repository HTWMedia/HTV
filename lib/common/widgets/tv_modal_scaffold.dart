import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../style/index.dart';

/// 半屏/全屏浮层弹窗的公共外壳。
///
/// Panel（频道面板）、Settings（设置页）、二维码这三处原本各抄了一遍同样的骨架：
///   PopScope(canPop) → Focus（ESC 返回）→ GestureDetector（点空白返回）
///   → 半透明黑底 → 内层空 GestureDetector（吞掉点击，避免点到内容还关闭）
/// 抽出来之后三处只剩「内容是什么」的差异，返回方式、遮罩颜色、焦点边界保持一致。
///
/// 注意：**刻意不改变 GestureDetector 的 behavior**。原实现依赖 Container 自身
/// 的 ColoredBox 参与命中测试；若改成 opaque，内容区域里的透明间隙也会被
/// 「点空白关闭」吃掉，属于行为变更而不是优化。
class TvModalScaffold extends StatelessWidget {
  const TvModalScaffold({
    super.key,
    required this.child,
    this.scrimColor = AppTheme.scrim,
  });

  final Widget child;

  /// 遮罩底色
  final Color scrimColor;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event.logicalKey == LogicalKeyboardKey.escape && event is KeyDownEvent) {
            Navigator.pop(context);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: GestureDetector(
          // 点内容之外的区域返回
          onTap: () => Navigator.pop(context),
          child: Container(
            color: scrimColor,
            child: GestureDetector(
              // 内容区的点击到这里为止：不要继续冒泡到外层的「点空白返回」
              onTap: () {},
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
