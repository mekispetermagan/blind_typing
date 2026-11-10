import 'package:blind_typing/controllers/typing_controller.dart';

import 'support/content_fixtures.dart';

import 'package:blind_typing/services/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio_service.dart';

import 'package:blind_typing/services/speech_coordinator.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeAudioService audio;
  late TypingController controller;

  setUp(() {
    audio = FakeAudioService();
    controller = TypingController(
      exercise: sampleExercise,
      speech: SpeechCoordinator(audio),
      countdownInterval: Duration.zero,
    );
  });
  tearDown(() => controller.dispose());

  Future<void> startAdvanced() async {
    await controller.initialize();
    controller.toggleMode();
    controller.start();
    await settle();
  }

  void type(String text) {
    for (final character in text.split('')) {
      controller.typeCharacter(character);
    }
  }

  test(
    'Simple is the default and still ignores errors and Backspace',
    () async {
      expect(controller.mode, TypingMode.simple);
      controller.toggleMode();
      expect(controller.mode, TypingMode.simple); // Audio is not loaded yet.
      await controller.initialize();
      controller.start();
      await settle();
      type('A xN');
      controller.backspace();
      expect(controller.enteredText, 'AN');
      expect(controller.letterIndex, 2);
      expect(audio.feedbackResults, [true, false, true]);
    },
  );

  test(
    'Advanced accumulates the entire error suffix, even beyond word length',
    () async {
      await startAdvanced();
      type('Axnaz');
      expect(controller.enteredText, 'Axnaz');
      expect(controller.letterIndex, 1);
      expect(controller.wordIndex, 0);
      expect(audio.feedbackResults, [true, false, false, false, false]);
      for (var index = 0; index < 4; index++) {
        controller.backspace();
      }
      expect(controller.enteredText, 'A');
      expect(controller.letterIndex, 1);
      type('NnA');
      expect(controller.wordIndex, 1);
      expect(controller.enteredText, isEmpty);
      controller.backspace();
      expect(controller.wordIndex, 1); // Completed words stay completed.
      expect(controller.letterIndex, 0);
    },
  );

  test(
    'Backspace also deletes correct characters down to an empty word',
    () async {
      await startAdvanced();
      type('An');
      controller.backspace();
      expect(controller.enteredText, 'A');
      expect(controller.letterIndex, 1);
      controller.backspace();
      controller.backspace();
      expect(controller.enteredText, isEmpty);
      expect(controller.letterIndex, 0);
      type('annaALM a');
      expect(controller.wordIndex, 1);
      expect(controller.enteredText, 'ALMa');
      expect(controller.letterIndex, 3); // Accents still have to match.
      controller.backspace();
      type('Á T');
      expect(controller.wordIndex, 2);
      expect(controller.enteredText, isEmpty);
    },
  );

  test('switching to Simple drops only the incorrect suffix', () async {
    await startAdvanced();
    type('aNxna');
    controller.toggleMode();
    expect(controller.mode, TypingMode.simple);
    expect(controller.enteredText, 'aN');
    expect(controller.letterIndex, 2);
    expect(audio.spoken.last, AudioCues.modeSimple);
    controller.toggleMode();
    expect(controller.enteredText, 'aN');
    expect(audio.spoken.last, AudioCues.modeAdvanced);
    type('NA');
    expect(controller.wordIndex, 1);
  });

  test('pause preserves input and ignores both typing and deletion', () async {
    await startAdvanced();
    type('ax');
    controller.pause();
    controller.typeCharacter('n');
    controller.backspace();
    expect(controller.enteredText, 'ax');
    controller.toggleMode();
    expect(controller.phase, ExercisePhase.paused);
    expect(controller.enteredText, 'a');
    controller.toggleMode();
    controller.togglePause();
    expect(controller.mode, TypingMode.advanced);
    expect(controller.phase, ExercisePhase.typing);
    controller.backspace();
    expect(controller.enteredText, isEmpty);
  });

  test('the mode survives sentence changes and exercise restarts', () async {
    await startAdvanced();
    for (final sentence in sampleSentences) {
      type(sentence.text);
      await settle();
      expect(controller.mode, TypingMode.advanced);
    }
    expect(controller.phase, ExercisePhase.complete);
    final finalText = controller.enteredText;
    controller.backspace();
    expect(controller.enteredText, finalText);
    controller.start();
    await settle();
    expect(controller.mode, TypingMode.advanced);
    expect(controller.enteredText, isEmpty);
    expect(controller.letterIndex, 0);
  });

  for (final duringCountdown in [false, true]) {
    test(
      'mode change during ${duringCountdown ? 'countdown' : 'reading'} restarts instructions safely',
      () async {
        await controller.initialize();
        audio.holdSpeech = true;
        controller.start();
        if (duringCountdown) {
          audio.finishSpeech();
          await settle();
          expect(controller.phase, ExercisePhase.countdown);
        }
        controller.toggleMode();
        await settle();
        expect(controller.phase, ExercisePhase.reading);
        expect(controller.countdown, isNull);
        expect(audio.spoken.last, AudioCues.modeAdvanced);
        controller.backspace();
        controller.typeCharacter('a');
        expect(controller.enteredText, isEmpty);
        for (final next in [
          sampleSentences.first.audioAsset,
          AudioCues.count(3),
          AudioCues.count(2),
          AudioCues.count(1),
          sampleSentences.first.wordAudioAsset(0),
        ]) {
          audio.finishSpeech();
          await settle();
          expect(audio.spoken.last, next);
        }
        expect(controller.phase, ExercisePhase.typing);
      },
    );
  }

  testWidgets(
    'F2 spells actual input including a mistake as the first letter',
    (tester) async {
      await controller.initialize();
      controller.toggleMode();
      controller.start();
      await tester.pump();
      type('xNa');
      audio.spoken.clear();
      controller.spellEnteredLetters();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      expect(audio.spoken, 'xna'.split('').map(AudioCues.letter));
      expect(controller.enteredText, 'xNa');
      expect(controller.letterIndex, 0);
    },
  );

  testWidgets('Backspace and F3 interrupt spelling without stale playback', (
    tester,
  ) async {
    await controller.initialize();
    controller.toggleMode();
    controller.start();
    await tester.pump();
    type('ax');
    audio.spoken.clear();
    controller.spellEnteredLetters();
    await tester.pump();
    controller.backspace();
    await tester.pump(const Duration(milliseconds: 250));
    expect(audio.spoken, [AudioCues.letter('a')]);
    expect(controller.enteredText, 'a');
    type('xy');
    controller.spellEnteredLetters();
    await tester.pump();
    controller.toggleMode();
    await tester.pump(const Duration(milliseconds: 250));
    expect(audio.spoken, [
      AudioCues.letter('a'),
      AudioCues.letter('a'),
      AudioCues.modeSimple,
    ]);
    expect(controller.enteredText, 'a');
  });

  testWidgets(
    'nonalphabet mistakes have a spoken fallback and delete as entered',
    (tester) async {
      await controller.initialize();
      controller.toggleMode();
      controller.start();
      await tester.pump();
      controller.typeCharacter('?');
      controller.typeCharacter('🙂');
      audio.spoken.clear();
      controller.spellEnteredLetters();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(audio.spoken, [
        AudioCues.unknownCharacter,
        AudioCues.unknownCharacter,
      ]);
      expect(controller.phase, ExercisePhase.typing);
      controller.backspace();
      expect(controller.enteredText, '?');
      controller.backspace();
      expect(controller.enteredText, isEmpty);
    },
  );
}
