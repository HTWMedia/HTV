import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../style/index.dart';

/// 电视端 Dialog 的公共外壳。
///
/// 两个 Dialog（文本编辑、频道选择）原本各自抄了一遍同样的五层嵌套：
///   Dialog → ConstrainedBox(maxWidth/maxHeight) → Padding
///   → Focus（容器层托管按键）→ DefaultTextStyle
/// 抽出来之后，剩下的只有「内容是什么」与「方向键怎么走」的差异。
///
/// 关键点：焦点默认落在**容器层**而不是输入框。Flutter 的按键分发是
/// 「叶子 → 根」，EditableText 在最内层就把上下方向键吃成了光标移动，
/// 输入框一拿到焦点，外层 Focus 再也收不到方向键，底部按钮因此不可达。
/// 所以由容器统一接管方向键与 OK 键 —— 逻辑见 [TvDialogEditStateMixin]。
class TvDialogFrame extends StatelessWidget {
  const TvDialogFrame({
    super.key,
    required this.focusNode,
    required this.onKeyEvent,
    required this.child,
    this.maxWidth = 500,
    this.maxHeight,
    this.fontSize = 24,
    this.padding = 20,
  });

  /// 容器层焦点，按键在这里接管
  final FocusNode focusNode;

  /// 容器层按键处理（方向键移动高亮、OK 键激活当前元素）
  final FocusOnKeyEventCallback onKeyEvent;

  final Widget child;

  /// 弹窗最大宽度（设计稿单位）
  final double maxWidth;

  /// 弹窗最大高度（设计稿单位）；为空表示不限高
  final double? maxHeight;

  /// 正文字号（设计稿单位），同时作为 DefaultTextStyle 的默认字号
  final double fontSize;

  /// 内边距（设计稿单位）
  final double padding;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.bg(context),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth.w,
          maxHeight: maxHeight?.h ?? double.infinity,
        ),
        child: Padding(
          padding: EdgeInsets.all(padding).r,
          child: Focus(
            focusNode: focusNode,
            autofocus: true,
            onKeyEvent: onKeyEvent,
            child: DefaultTextStyle(
              style: AppTheme.text(AppTheme.fg(context), fontSize.sp),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// OK / 确认键判定。
///
/// `keyId == 23` 是部分安卓盒子 OK 键上行的 keyId，不在标准枚举里，
/// 只能按 keyId 兜。原来是每个 Dialog 各写一份。
bool isTvConfirmKey(LogicalKeyboardKey key) =>
    key == LogicalKeyboardKey.select ||
    key == LogicalKeyboardKey.enter ||
    key == LogicalKeyboardKey.numpadEnter ||
    key.keyId == 23;

/// 电视端 Dialog 的「编辑态」托管。
///
/// 两个 Dialog 都有同一个状态机：默认焦点在容器层（此时方向键走自己画的高亮），
/// 按 OK 进入编辑态（焦点交给输入框，方向键归 EditableText 移动光标），
/// 按返回/ESC 先退出编辑态，非编辑态下才是关闭弹窗。
///
/// 混入后 State 需要做三件事：
///   1. 覆写 [tvEditFocusNode] 返回真正的输入框 FocusNode（生命周期由本 mixin 托管）；
///   2. `initState` / `dispose` 里调用 `super.initState()` / `super.dispose()`；
///   3. 自己的 `_handleKey` 先问一遍 [tvHandleCommonKey]，返回非空即已消费。
mixin TvDialogEditStateMixin<T extends StatefulWidget> on State<T> {
  /// 容器层焦点：非编辑态时方向键与 OK 键都在这里处理
  final FocusNode tvRootFocusNode = FocusNode(debugLabel: 'TvDialogRoot');

  /// 是否处于编辑态（编辑态下方向键归输入框）
  bool tvEditing = false;

  /// 真正持有文本输入焦点的节点
  FocusNode get tvEditFocusNode;

  /// 编辑态切换时同步自己的额外状态。
  ///
  /// 在 setState 回调里被调用，**里面不要再 setState**。
  void onTvEditingChanged(bool editing) {}

  @override
  void initState() {
    super.initState();
    tvEditFocusNode.addListener(_tvSyncEditingFromFocus);

    // autofocus 在部分机型上不生效（新路由 scope 里已有焦点），这里兜底一次
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) tvRootFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    tvEditFocusNode.removeListener(_tvSyncEditingFromFocus);
    tvEditFocusNode.dispose();
    tvRootFocusNode.dispose();
    super.dispose();
  }

  /// 鼠标/触摸直接点输入框时同步为编辑态，
  /// 避免出现「焦点在输入框、高亮指示却在别处」的错位
  void _tvSyncEditingFromFocus() {
    if (tvEditFocusNode.hasFocus && !tvEditing) tvEnterEditing();
  }

  void tvEnterEditing() {
    setState(() {
      tvEditing = true;
      onTvEditingChanged(true);
    });
    tvEditFocusNode.requestFocus();
  }

  void tvExitEditing() {
    if (!tvEditing) return;
    setState(() {
      tvEditing = false;
      onTvEditingChanged(false);
    });
    tvRootFocusNode.requestFocus();
  }

  /// 两个 Dialog 共有的按键语义：返回键与编辑态。
  ///
  /// 返回 null 表示本层不关心，交给具体 Dialog 继续判方向键 / OK 键。
  KeyEventResult? tvHandleCommonKey(KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.goBack) {
      if (tvEditing) {
        tvExitEditing();
      } else if (Navigator.of(context).canPop()) {
        // 非编辑态：返回键/ESC 关闭弹窗。
        // canPop 判断避免连点时重复 pop 把上层页面一起带出去。
        Navigator.of(context).pop();
      }
      return KeyEventResult.handled;
    }

    // 编辑态下方向键归输入框，等按返回键退出
    if (tvEditing) return KeyEventResult.ignored;

    return null;
  }
}

/// 弹窗里的输入框外壳（细描边容器 + 点击进编辑态）。
///
/// 文本编辑弹窗的正文框与频道弹窗的搜索框只有「有没有前置图标」这一处差异，
/// 统一由 [leading] 承载。
class TvDialogField extends StatelessWidget {
  const TvDialogField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.active,
    this.fontSize = 24,
    this.leading,
    this.onTap,
    this.onChanged,
    this.onSubmitted,
    this.horizontalPadding = 12,
    this.verticalPadding = 8,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;

  /// 是否被「选中或编辑中」，为真时描边加粗加亮
  final bool active;

  /// 正文字号（设计稿单位）
  final double fontSize;

  /// 前置控件（如搜索图标）
  final Widget? leading;

  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  /// 水平/垂直内边距（设计稿单位）
  final double horizontalPadding;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final fg = AppTheme.fg(context);

    final field = TextField(
      controller: controller,
      focusNode: focusNode,
      textInputAction: TextInputAction.done,
      onSubmitted: onSubmitted,
      onChanged: onChanged,
      // 电视端没有软键盘输入法，这套输入辅助只会带来额外开销
      enableInteractiveSelection: false,
      enableSuggestions: false,
      autocorrect: false,
      decoration: InputDecoration.collapsed(
        hintText: hint,
        hintStyle: AppTheme.text(AppTheme.fgFaded(context, AppTheme.oSubtle), fontSize.sp),
      ),
      style: AppTheme.text(fg, fontSize.sp),
    );

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: active ? fg : AppTheme.fgFaded(context, 0.3),
          width: active ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8).r,
      ),
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding.w,
        vertical: verticalPadding.h,
      ),
      child: GestureDetector(
        onTap: onTap,
        child: leading == null
            ? field
            : Row(
                children: [
                  leading!,
                  SizedBox(width: 8.w),
                  Expanded(child: field),
                ],
              ),
      ),
    );
  }
}

/// 弹窗里的高亮块按钮（「全选」「取消」「保存」等）。
///
/// 不用 TextButton：那些控件依赖原生焦点遍历，而这里的高亮是容器层
/// 自己按「区域 + 下标」画的，按钮本身不需要真焦点。
class TvDialogChip extends StatelessWidget {
  const TvDialogChip({
    super.key,
    required this.label,
    required this.highlighted,
    required this.onTap,
    this.fontSize = 24,
  });

  final String label;
  final bool highlighted;
  final VoidCallback onTap;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final fg = AppTheme.fg(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: highlighted ? AppTheme.fgFaded(context, 0.12) : null,
          border: Border.all(
            color: highlighted ? fg : Colors.transparent,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(8).r,
        ),
        child: Text(label, style: AppTheme.text(fg, fontSize.sp)),
      ),
    );
  }
}
