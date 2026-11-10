import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/exercise.dart';
import '../models/teaching_state.dart';
import '../models/typing_state.dart';
import '../widgets/app_keyboard.dart';

class TeachingScreen extends StatelessWidget {
  const TeachingScreen({
    required this.title,
    required this.step,
    required this.state,
    required this.onStart,
    required this.onCharacter,
    required this.onRepeat,
    required this.onPause,
    required this.onToggleMode,
    required this.onClose,
    super.key,
  });
  final String title;
  final LetterStep step;
  final TeachingState state;
  final VoidCallback onStart;
  final ValueChanged<String> onCharacter;
  final VoidCallback onRepeat;
  final VoidCallback onPause;
  final VoidCallback onToggleMode;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) => AppKeyboard(
    onClose: onClose,
    onCharacter: onCharacter,
    shortcuts: {
      LogicalKeyboardKey.enter: onStart,
      LogicalKeyboardKey.numpadEnter: onStart,
      LogicalKeyboardKey.f1: onRepeat,
      LogicalKeyboardKey.escape: onPause,
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
          children: [
            Text(
              step.instruction,
              style: const TextStyle(fontSize: 24),
              textAlign: TextAlign.center,
            ),
            Expanded(
              child: Center(
                child: Text(step.key, style: const TextStyle(fontSize: 120)),
              ),
            ),
            Text(
              '${state.successes} / ${step.requiredSuccesses}',
              style: const TextStyle(fontSize: 28),
            ),
            const SizedBox(height: 16),
            Text(
              state.phase == ExercisePhase.ready
                  ? 'Enter — kezdés'
                  : state.lastKey == null
                  ? 'Keresd meg a billentyűt'
                  : 'Legutóbb: ${state.lastKey}',
              style: TextStyle(
                fontSize: 24,
                color: state.lastCorrect == false
                    ? Theme.of(context).colorScheme.error
                    : null,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'F1: útmutató ismétlése   Escape: szünet   Ctrl+W / F4: kilépés',
            ),
          ],
        ),
      ),
    ),
  );
}
