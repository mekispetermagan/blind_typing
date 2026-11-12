import 'package:blind_typing/controllers/letter_teaching_controller.dart';
import 'package:blind_typing/controllers/typing_controller.dart';
import 'package:blind_typing/models/exercise.dart';
import 'package:blind_typing/models/typing_unit.dart';
import 'package:blind_typing/services/audio_service.dart';
import 'package:blind_typing/services/speech_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/content_fixtures.dart';
import 'support/fake_audio_service.dart';

void main() {
  test('numeric targets preserve zeroes and old sentence parsing', () {
    final exercise = TypingExercise.fromJson(
      readData('data/lessons/numbers_words.json'),
    );
    expect(exercise.units, hasLength(24));
    expect(
      exercise.units.map((unit) => unit.text),
      containsAll(['0640494949', '0680810600', '0618729590', '0613255255']),
    );
    final unit = exercise.units.last;
    expect(unit.words, ['0613255255']);
    expect(TypingUnit(id: 'old', text: 'Anna 123 almát').words, [
      'Anna',
      'almát',
    ]);
  });

  for (final mode in TypingMode.values) {
    test('all 24 numbers complete in ${mode.name} mode', () async {
      final exercise = TypingExercise.fromJson(
        readData('data/lessons/numbers_words.json'),
      );
      final controller = TypingController(
        exercise: exercise,
        speech: SpeechCoordinator(FakeAudioService()),
        mode: mode,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.start();
      for (final unit in exercise.units) {
        for (final digit in unit.text.split('')) {
          controller.typeCharacter(digit);
        }
      }
      expect(controller.phase, ExercisePhase.complete);
      expect(controller.practiceResult?.errors, 0);
    });
  }

  testWidgets(
    'F2 spells entered digits, including errors, and backspace works',
    (tester) async {
      final exercise = TypingExercise.fromJson(
        readData('data/lessons/numbers_words.json'),
      );
      final audio = FakeAudioService();
      final controller = TypingController(
        exercise: exercise,
        speech: SpeechCoordinator(audio),
        mode: TypingMode.advanced,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      controller.start();
      controller.typeCharacter('0');
      controller.typeCharacter('9');
      expect(controller.enteredText, '09');
      controller.spellEnteredLetters();
      await tester.pump();
      expect(audio.spoken.last, 'assets/audio/result_number_0.wav');
      await tester.pump(const Duration(milliseconds: 250));
      expect(audio.spoken.last, 'assets/audio/result_number_9.wav');
      controller.backspace();
      controller.backspace();
      controller.typeCharacter('1');
      expect(controller.sentenceIndex, 1);
    },
  );

  test('number-key teaching completes all ten digits', () async {
    final exercise = LetterExercise.fromJson(
      readData('data/lessons/numbers_letters.json'),
    );
    final controller = LetterTeachingController(
      exercise: exercise,
      speech: SpeechCoordinator(FakeAudioService()),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.start();
    for (final step in exercise.steps) {
      expect(controller.step.id, step.id);
      for (var i = 0; i < step.requiredSuccesses; i++) {
        controller.typeCharacter(step.key);
      }
      await Future<void>.delayed(Duration.zero);
    }
    expect(controller.state.phase, ExercisePhase.complete);
  });

  test('teaching identifies a wrong digit', () async {
    final exercise = LetterExercise.fromJson(
      readData('data/lessons/numbers_letters.json'),
    );
    final audio = FakeAudioService();
    final controller = LetterTeachingController(
      exercise: exercise,
      speech: SpeechCoordinator(audio),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.start();
    controller.typeCharacter('4');
    await Future<void>.delayed(Duration.zero);
    expect(audio.spoken, contains(AudioCues.letter('4')));
    expect(AudioCues.letter('4'), 'assets/audio/result_number_4.wav');
  });
}
