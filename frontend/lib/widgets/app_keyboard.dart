import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Translates hardware events into callbacks; it knows no exercise rules.
class AppKeyboard extends StatelessWidget {
  const AppKeyboard({
    required this.child,
    required this.onClose,
    this.shortcuts = const {},
    this.onCharacter,
    this.onKeyDown,
    super.key,
  });
  final Widget child;
  final VoidCallback onClose;
  final Map<LogicalKeyboardKey, VoidCallback> shortcuts;
  final ValueChanged<String>? onCharacter;
  final VoidCallback? onKeyDown;

  KeyEventResult _handle(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) onKeyDown?.call();
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.f4 ||
        (keyboard.isControlPressed && key == LogicalKeyboardKey.keyW)) {
      onClose();
      return KeyEventResult.handled;
    }
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final action = shortcuts[key];
    if (action != null) {
      action();
      return KeyEventResult.handled;
    }
    final character = event.character;
    if (onCharacter != null &&
        character != null &&
        character.isNotEmpty &&
        character.runes.every((rune) => rune >= 32)) {
      onCharacter!(character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) =>
      Focus(autofocus: true, onKeyEvent: _handle, child: child);
}
