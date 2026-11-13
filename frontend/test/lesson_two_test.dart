import 'package:blind_typing/controllers/app_controller.dart';
import 'package:blind_typing/controllers/letter_teaching_controller.dart';
import 'package:blind_typing/models/exercise.dart';
import 'package:blind_typing/models/typing_state.dart';
import 'package:blind_typing/services/speech_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/content_fixtures.dart';
import 'support/fake_audio_service.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

LetterExercise get reachingExercise =>
    LetterExercise.fromJson(readData('data/lessons/upper_row_ir_letters.json'));

void main() {
  test(
    'teaching uses single F/K anchors and three R/I successes across mistakes',
    () async {
      final audio = FakeAudioService();
      final controller = LetterTeachingController(
        exercise: reachingExercise,
        speech: SpeechCoordinator(audio),
      );
      addTearDown(controller.dispose);
      expect(reachingExercise.steps.map((step) => step.key), [
        'F',
        'R',
        'K',
        'I',
      ]);
      expect(reachingExercise.steps.map((step) => step.requiredSuccesses), [
        1,
        3,
        1,
        3,
      ]);
      await controller.initialize();
      controller.start();
      controller.typeCharacter('d');
      expect(controller.state.successes, 0);
      audio.holdSpeech = true;
      controller.typeCharacter('f');
      expect(controller.state.phase, ExercisePhase.reading);
      controller.typeCharacter('r'); // Wait for the anchor-success transition.
      expect(controller.state.successes, 0);
      audio.finishSpeech();
      await settle();
      expect(controller.step.key, 'R');
      expect(audio.spoken.last, controller.step.audio('instruction'));
      audio.holdSpeech = false;
      controller.typeCharacter('r');
      controller.typeCharacter('f');
      expect(controller.state.successes, 1);
      controller.pause();
      controller.resume();
      expect(controller.step.key, 'R');
      expect(controller.state.successes, 1);
      controller.typeCharacter('R');
      controller.typeCharacter('r');
      await settle();
      expect(controller.step.key, 'K');
      controller.typeCharacter('k');
      await settle();
      expect(controller.step.key, 'I');
      controller.typeCharacter('i');
      controller.typeCharacter('k');
      expect(controller.state.successes, 1);
      controller.typeCharacter('I');
      controller.typeCharacter('i');
      expect(controller.state.phase, ExercisePhase.complete);
      expect(controller.state.successes, 3);
    },
  );

  final sessions = [
    ('i', 'ASDFJKLÉI', 28, 'IS', 'KÉKLIK'),
    ('r', 'ASDFJKLÉR', 31, 'ÉR', 'ARRA'),
    ('ir', 'ASDFJKLÉIR', 21, 'IRKA', 'KARDJAI'),
  ];
  for (var index = 0; index < sessions.length; index++) {
    final (group, allowed, count, first, last) = sessions[index];
    test(
      '$group session is data-driven and completes all $count supplied words',
      () async {
        final audio = FakeAudioService();
        final app = AppController(
          content: FileContentRepository(),
          speech: SpeechCoordinator(audio),
          countdownInterval: Duration.zero,
        );
        addTearDown(app.dispose);
        await app.initialize();
        app.activate();
        app.moveSelection(1);
        app.activate();
        expect(app.menu.id, 'upper_row_ir');
        expect(app.menu.children, hasLength(4));
        app.toggleMode();
        app.activateIndex(index + 1);
        await settle();
        final typing = app.typing!;
        expect(typing.exercise.id, 'upper_row_${group}_words');
        expect(typing.exercise.allowedLetters, allowed);
        expect(typing.exercise.units, hasLength(count));
        expect(typing.exercise.units.first.text, first);
        expect(typing.exercise.units.last.text, last);
        expect(typing.mode, TypingMode.advanced);
        typing.start();
        for (var target = 0; target < count; target++) {
          expect(typing.sentenceIndex, target);
          expect(typing.phase, ExercisePhase.typing);
          expect(typing.countdown, isNull);
          for (final character
              in typing.exercise.units[target].text.toLowerCase().split('')) {
            typing.typeCharacter(character);
          }
        }
        expect(app.activityPhase, ExercisePhase.complete);
        expect(app.menu.id, 'complete_menu');
        app.returnToMenu();
        expect(app.menu.id, 'upper_row_ir');
        expect(app.selectedIndex, index + 1);
        expect(audio.disposed, isFalse);
      },
    );
  }
}
