import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/typing_state.dart';
import '../models/typing_unit.dart';
import '../widgets/current_word.dart';
import '../widgets/app_keyboard.dart';
import '../widgets/sentence_display.dart';

class TypingScreen extends StatelessWidget {
  const TypingScreen({
    required this.sentence,
    this.title = 'Gépírás',
    this.showSentence = true,
    required this.sentenceIndex,
    required this.sentenceCount,
    required this.wordIndex,
    required this.letterIndex,
    required this.enteredCharacters,
    required this.mode,
    required this.phase,
    required this.countdown,
    required this.onStart,
    required this.onCharacter,
    required this.onRepeat,
    required this.onSpell,
    required this.onKeyDown,
    required this.onToggleMode,
    required this.onBackspace,
    required this.onPause,
    required this.onClose,
    super.key,
  });

  final TypingUnit sentence;
  final String title;
  final bool showSentence;
  final int sentenceIndex;
  final int sentenceCount;
  final int wordIndex;
  final int letterIndex;
  final List<String> enteredCharacters;
  final TypingMode mode;
  final ExercisePhase phase;
  final int? countdown;
  final VoidCallback onStart;
  final ValueChanged<String> onCharacter;
  final VoidCallback onRepeat;
  final VoidCallback onSpell;
  final VoidCallback onKeyDown;
  final VoidCallback onToggleMode;
  final VoidCallback onBackspace;
  final VoidCallback onPause;
  final VoidCallback onClose;

  String get _status => switch (phase) {
    ExercisePhase.loading => 'Hangok betöltése…',
    ExercisePhase.ready => 'Enter — kezdés',
    ExercisePhase.reading => 'Hallgasd meg a mondatot',
    ExercisePhase.countdown => '$countdown',
    ExercisePhase.typing => '',
    ExercisePhase.paused => 'Szünet · Escape — folytatás',
    ExercisePhase.complete => 'Kész! Enter — újrakezdés',
    ExercisePhase.error => 'A hang nem indítható · Enter — újrapróbálás',
  };

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final completed = phase == ExercisePhase.complete;
    final showWord =
        phase == ExercisePhase.typing ||
        phase == ExercisePhase.paused ||
        completed;
    return AppKeyboard(
      onClose: onClose,
      onKeyDown: onKeyDown,
      onCharacter: onCharacter,
      shortcuts: {
        LogicalKeyboardKey.enter: onStart,
        LogicalKeyboardKey.numpadEnter: onStart,
        LogicalKeyboardKey.f1: onRepeat,
        LogicalKeyboardKey.f2: onSpell,
        LogicalKeyboardKey.f3: onToggleMode,
        LogicalKeyboardKey.escape: onPause,
        LogicalKeyboardKey.backspace: onBackspace,
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            IconButton(
              tooltip: 'Kilépés (Ctrl+W / F4)',
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 24),
            child: Column(
              children: [
                if (showSentence)
                  SentenceDisplay(
                    words: sentence.words,
                    completedWords: completed
                        ? sentence.words.length
                        : wordIndex,
                  ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (showWord)
                        CurrentWord(
                          word: sentence.words[wordIndex],
                          acceptedLetters: letterIndex,
                          enteredCharacters: mode == TypingMode.advanced
                              ? enteredCharacters
                              : null,
                        ),
                      const SizedBox(height: 32),
                      SizedBox(
                        height: 72,
                        child: Center(
                          child: Text(
                            _status,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: phase == ExercisePhase.countdown
                                  ? 48
                                  : 20,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 64,
                  child: Center(
                    child: Text(
                      mode == TypingMode.simple ? 'Egyszerű mód' : 'Haladó mód',
                      style: TextStyle(color: colors.onSurfaceVariant),
                    ),
                  ),
                ),
                Text(
                  '${sentenceIndex + 1} / $sentenceCount',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Text(
                  'Enter: kezdés   F1: szó ismétlése   F2: beírt betűk   F3: módváltás\n'
                  'Backspace: törlés haladó módban   Escape: szünet   Ctrl+W / F4: kilépés',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
