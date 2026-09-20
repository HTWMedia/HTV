import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class EasyKeyboardListener extends StatefulWidget {
  final Map<LogicalKeyboardKey, bool Function()>? onKeyTap;
  final Map<LogicalKeyboardKey, bool Function()>? onKeyLongTap;
  final Map<LogicalKeyboardKey, bool Function()>? onKeyRepeat;

  /// 按键松开事件。用于「按下时先不处理、松手再判定短按」的场景，
  /// 从而让长按（onKeyLongTap/onKeyRepeat）不会连带触发短按。
  final Map<LogicalKeyboardKey, bool Function()>? onKeyUp;

  final FocusNode focusNode;
  final bool autofocus;
  final bool includeSemantics;
  final Widget child;

  EasyKeyboardListener({
    super.key,
    required this.child,
    required this.focusNode,
    this.autofocus = false,
    this.includeSemantics = true,
    this.onKeyTap,
    this.onKeyLongTap,
    this.onKeyRepeat,
    this.onKeyUp,
  });

  @override
  State<EasyKeyboardListener> createState() => _EasyKeyboardListenerState();
}

class _EasyKeyboardListenerState extends State<EasyKeyboardListener> {
  final _pressedKeys = <int>{};
  final _longTapFired = <int>{};

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    final key = event.logicalKey;
    final keyId = key.keyId;

    if (event is KeyDownEvent) {
      if (!_pressedKeys.contains(keyId)) {
        _pressedKeys.add(keyId);

        if (widget.onKeyTap?.containsKey(key) == true) {
          if (widget.onKeyTap![key]!()) {
            return KeyEventResult.handled;
          }
        }

        if (keyId == 23 && widget.onKeyTap?.containsKey(LogicalKeyboardKey.select) == true) {
          if (widget.onKeyTap![LogicalKeyboardKey.select]!()) {
            return KeyEventResult.handled;
          }
        }
      }
    }

    if (event is KeyRepeatEvent) {
      if (widget.onKeyRepeat?.containsKey(key) == true) {
        if (widget.onKeyRepeat![key]!()) {
          return KeyEventResult.handled;
        }
      }

      if (!_longTapFired.contains(keyId) && widget.onKeyLongTap?.containsKey(key) == true) {
        _longTapFired.add(keyId);
        if (widget.onKeyLongTap![key]!()) {
          return KeyEventResult.handled;
        }
      }
    }

    if (event is KeyUpEvent) {
      final wasPressed = _pressedKeys.remove(keyId);
      _longTapFired.remove(keyId);

      if (wasPressed) {
        if (widget.onKeyUp?.containsKey(key) == true) {
          if (widget.onKeyUp![key]!()) {
            return KeyEventResult.handled;
          }
        }

        // 与按下时一致：部分设备 OK 键上行的 keyId 无法映射成 LogicalKeyboardKey.select
        if (keyId == 23 && widget.onKeyUp?.containsKey(LogicalKeyboardKey.select) == true) {
          if (widget.onKeyUp![LogicalKeyboardKey.select]!()) {
            return KeyEventResult.handled;
          }
        }
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      includeSemantics: widget.includeSemantics,
      child: widget.child,
    );
  }
}