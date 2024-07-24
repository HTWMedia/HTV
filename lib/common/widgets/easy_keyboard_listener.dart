import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class EasyKeyboardListener extends KeyboardListener {
  final Map<LogicalKeyboardKey, void Function()>? onKeyTap;
  final Map<LogicalKeyboardKey, void Function()>? onKeyLongTap;
  final Map<LogicalKeyboardKey, void Function()>? onKeyRepeat;

  EasyKeyboardListener({
    super.key,
    required super.child,
    required super.focusNode,
    super.autofocus,
    super.includeSemantics,
    this.onKeyTap,
    this.onKeyLongTap,
    this.onKeyRepeat,
  });

  final _keyDown = <int, bool>{};

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      onKeyEvent: (event) {
        if (event.runtimeType == KeyDownEvent) {
          final key = event.logicalKey;
          _keyDown[key.keyId] = true;
        } else if (event.runtimeType == KeyUpEvent) {
          final key = event.logicalKey;

          if (!_keyDown.containsKey(key.keyId)) return;
          _keyDown.remove(key.keyId);

          if (onKeyTap?.containsKey(key) == true) {
            onKeyTap![key]!();
          }
        } else if (event.runtimeType == KeyRepeatEvent) {
          final key = event.logicalKey;

          if (onKeyRepeat?.containsKey(key) == true) {
            onKeyRepeat![key]!();
          }

          if (!_keyDown.containsKey(key.keyId)) return;
          _keyDown.remove(key.keyId);

          if (onKeyLongTap?.containsKey(key) == true) {
            onKeyLongTap![key]!();
          }
        }
      },
      focusNode: focusNode,
      autofocus: autofocus,
      includeSemantics: includeSemantics,
      child: child,
    );
  }
}

class WindgetBinding {}