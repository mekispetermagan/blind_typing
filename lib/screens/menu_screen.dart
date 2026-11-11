import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/menu.dart';
import '../models/typing_state.dart';
import '../widgets/app_keyboard.dart';
import '../widgets/menu_list.dart';

class MenuScreen extends StatelessWidget {
  const MenuScreen({
    required this.title,
    required this.breadcrumb,
    this.summary,
    required this.items,
    required this.selectedIndex,
    required this.mode,
    required this.onMove,
    required this.onActivate,
    required this.onActivateIndex,
    required this.onBack,
    required this.onRepeat,
    required this.onToggleMode,
    required this.onClose,
    super.key,
  });
  final String title;
  final String breadcrumb;
  final String? summary;
  final List<MenuNode> items;
  final int selectedIndex;
  final TypingMode mode;
  final ValueChanged<int> onMove;
  final VoidCallback onActivate;
  final ValueChanged<int> onActivateIndex;
  final VoidCallback onBack;
  final VoidCallback onRepeat;
  final VoidCallback onToggleMode;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => AppKeyboard(
    onClose: onClose,
    shortcuts: {
      LogicalKeyboardKey.arrowUp: () => onMove(-1),
      LogicalKeyboardKey.arrowDown: () => onMove(1),
      LogicalKeyboardKey.arrowRight: onActivate,
      LogicalKeyboardKey.enter: onActivate,
      LogicalKeyboardKey.numpadEnter: onActivate,
      LogicalKeyboardKey.arrowLeft: onBack,
      LogicalKeyboardKey.escape: onBack,
      LogicalKeyboardKey.f1: onRepeat,
      LogicalKeyboardKey.f3: onToggleMode,
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            onPressed: onClose,
            tooltip: 'Kilépés (F4)',
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(breadcrumb, style: Theme.of(context).textTheme.bodyLarge),
            if (summary case final text?) ...[
              const SizedBox(height: 16),
              Text(text),
            ],
            const SizedBox(height: 32),
            Expanded(
              child: MenuList(
                items: items,
                selectedIndex: selectedIndex,
                onActivate: onActivateIndex,
              ),
            ),
            const SizedBox(height: 16),
            Text(mode == TypingMode.simple ? 'Egyszerű mód' : 'Haladó mód'),
            const SizedBox(height: 16),
            const Text(
              '↑ ↓: választás   Enter / →: megnyitás   Escape / ←: vissza\n'
              'F1: ismétlés   F3: módváltás   Ctrl+W / F4: kilépés',
            ),
          ],
        ),
      ),
    ),
  );
}
