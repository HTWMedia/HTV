import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../style/index.dart';
import 'tv_dialog_frame.dart';

/// 弹窗按钮描述
class TvDialogButton {
  const TvDialogButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;
}

/// 电视端文本编辑弹窗
///
/// 焦点环是「输入框 → 自定义按钮 → 取消 → 保存」的一维序列，
/// 由容器层统一托管方向键与 OK 键，保证「保存」永远可达；
/// 输入框需要按 OK 进入编辑（或鼠标点击），按返回键退出编辑。
class TvTextEditDialog extends StatefulWidget {
  const TvTextEditDialog({
    super.key,
    required this.title,
    required this.hint,
    required this.initialValue,
    required this.onSave,
    this.subtitle,
    this.extraButtons = const <TvDialogButton>[],
    this.maxWidth = 500,
    this.fontSize = 24,
  });

  final String title;
  final String? subtitle;
  final String hint;
  final String initialValue;
  final ValueChanged<String> onSave;
  final List<TvDialogButton> extraButtons;

  /// 弹窗宽度（设计稿单位）
  final double maxWidth;

  /// 正文字号（设计稿单位）
  final double fontSize;

  @override
  State<TvTextEditDialog> createState() => _TvTextEditDialogState();
}

class _TvTextEditDialogState extends State<TvTextEditDialog>
    with TvDialogEditStateMixin<TvTextEditDialog> {
  /// 焦点环中的「输入框」位置
  static const int _fieldIndex = 0;

  final _fieldFocusNode = FocusNode(debugLabel: 'TvTextEditField');

  late final TextEditingController _controller;
  late final List<TvDialogButton> _buttons;
  late final List<FocusNode> _buttonNodes;

  /// 当前焦点序号：0 为输入框，其余为 extraButtons + 取消 + 保存
  int _focusIndex = _fieldIndex;

  @override
  FocusNode get tvEditFocusNode => _fieldFocusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _buttons = <TvDialogButton>[
      ...widget.extraButtons,
      TvDialogButton(label: '取消', onPressed: () => Navigator.pop(context)),
      TvDialogButton(label: '保存', onPressed: _save),
    ];
    _buttonNodes = List.generate(_buttons.length, (_) => FocusNode());

    // 初帧给输入框的高亮落在容器层，不把焦点真交给 EditableText
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) tvRootFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    for (final node in _buttonNodes) {
      node.dispose();
    }
    super.dispose();
  }

  int get _ringCount => _buttonNodes.length + 1;

  void _save() {
    widget.onSave(_controller.text);
    Navigator.pop(context);
  }

  void _requestFocusIndex(int index) {
    if (_buttonNodes.isEmpty) return;
    final count = _ringCount;
    final next = ((index % count) + count) % count;
    setState(() => _focusIndex = next);
    // 落在输入框上时只做高亮，不真正把焦点交给它，
    // 否则 EditableText 会立刻接管方向键
    if (next == _fieldIndex) {
      tvRootFocusNode.requestFocus();
    } else {
      _buttonNodes[next - 1].requestFocus();
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final common = tvHandleCommonKey(event);
    if (common != null) return common;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown || key == LogicalKeyboardKey.arrowRight) {
      _requestFocusIndex(_focusIndex + 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp || key == LogicalKeyboardKey.arrowLeft) {
      _requestFocusIndex(_focusIndex - 1);
      return KeyEventResult.handled;
    }
    if (isTvConfirmKey(key)) {
      if (_focusIndex == _fieldIndex) {
        tvEnterEditing();
      } else {
        // _focusIndex 为 0 时代表输入框，按钮从 1 开始
        _buttons[_focusIndex - 1].onPressed();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final fg = AppTheme.fg(context);
    return TvDialogFrame(
      focusNode: tvRootFocusNode,
      onKeyEvent: _handleKey,
      maxWidth: widget.maxWidth,
      fontSize: widget.fontSize,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.title,
            style: AppTheme.text(fg, (widget.fontSize + 8).sp),
          ),
          if (widget.subtitle != null) ...[
            SizedBox(height: 12.h),
            Text(
              widget.subtitle!,
              style: AppTheme.text(AppTheme.fgFaded(context, AppTheme.oSecondary), widget.fontSize.sp),
            ),
          ],
          SizedBox(height: 20.h),
          _buildField(),
          SizedBox(height: 20.h),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              for (var i = 0; i < _buttonNodes.length; i++) ...[
                if (i > 0) SizedBox(width: 16.w),
                TextButton(
                  focusNode: _buttonNodes[i],
                  onPressed: _buttons[i].onPressed,
                  child: Text(
                    _buttons[i].label,
                    // 显式带上字号：按钮样式的 ButtonStyleButton 会塞一份
                    // 主题默认字号进来，不覆盖就掉帧似的变小一截
                    style: AppTheme.text(fg, widget.fontSize.sp),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildField() {
    return TvDialogField(
      controller: _controller,
      focusNode: _fieldFocusNode,
      hint: widget.hint,
      fontSize: widget.fontSize,
      // 编辑态自然要高亮；非编辑态下随焦点环是否落在输入框上
      active: tvEditing || _focusIndex == _fieldIndex,
      onTap: tvEnterEditing,
      onSubmitted: (_) => tvExitEditing(),
    );
  }
}
