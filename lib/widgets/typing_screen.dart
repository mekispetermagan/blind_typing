import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/typing_controller.dart';
import '../models/sentence.dart';
import 'current_word.dart';
import 'sentence_display.dart';

class TypingScreen extends StatelessWidget {
  const TypingScreen({
    required this.sentence,
    required this.sentenceIndex,
    required this.sentenceCount,
    required this.wordIndex,
    required this.letterIndex,
    required this.phase,
    required this.countdown,
    required this.onStart,
    required this.onCharacter,
    required this.onRepeat,
    required this.onSpell,
    required this.onKeyDown,
    required this.onPause,
    required this.onClose,
    super.key,
  });

  final Sentence sentence;
  final int sentenceIndex;
  final int sentenceCount;
  final int wordIndex;
  final int letterIndex;
  final ExercisePhase phase;
  final int? countdown;
  final VoidCallback onStart;
  final ValueChanged<String> onCharacter;
  final VoidCallback onRepeat;
  final VoidCallback onSpell;
  final VoidCallback onKeyDown;
  final VoidCallback onPause;
  final VoidCallback onClose;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent || event is KeyRepeatEvent) onKeyDown();
    if (event is KeyRepeatEvent) return KeyEventResult.handled;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keyboard = HardwareKeyboard.instance;
    if (key == LogicalKeyboardKey.f4 ||
        (keyboard.isControlPressed && key == LogicalKeyboardKey.keyW)) {
      onClose();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      onStart();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f1) {
      onRepeat();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2) {
      onSpell();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      onPause();
      return KeyEventResult.handled;
    }
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return KeyEventResult.ignored;
    }
    final character = event.character;
    if (character != null &&
        character.isNotEmpty &&
        character.runes.every((rune) => rune >= 32)) {
      onCharacter(character);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

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
    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Gépírás'),
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
                SentenceDisplay(
                  words: sentence.words,
                  completedWords: completed ? sentence.words.length : wordIndex,
                ),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (showWord)
                        CurrentWord(
                          word: sentence.words[wordIndex],
                          acceptedLetters: letterIndex,
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
                // Reserved for later visual scoring and rewards.
                const SizedBox(height: 64),
                Text(
                  '${sentenceIndex + 1} / $sentenceCount',
                  style: TextStyle(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Text(
                  'Enter: kezdés   F1: szó ismétlése   F2: beírt betűk   Escape: szünet   Ctrl+W / F4: kilépés',
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
