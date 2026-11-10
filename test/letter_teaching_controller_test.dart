import 'package:blind_typing/controllers/letter_teaching_controller.dart';
import 'package:blind_typing/models/exercise.dart';
import 'package:blind_typing/models/typing_state.dart';
import 'package:blind_typing/services/audio_service.dart';
import 'package:blind_typing/services/speech_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/content_fixtures.dart';
import 'support/fake_audio_service.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeAudioService audio;
  late LetterTeachingController controller;
  setUp(() {
    audio = FakeAudioService();
    controller = LetterTeachingController(
      exercise: letterExercise,
      speech: SpeechCoordinator(audio),
    );
  });
  tearDown(() => controller.dispose());

  test('mode announcement during a step transition still delivers the next instruction', () async {
    final next = LetterStep(
      id: 'reach_r',
      key: 'R',
      instruction: 'R',
      retry: 'R',
      success: 'R',
      complete: 'R',
      requiredSuccesses: 1,
    );
    final other = LetterTeachingController(
      exercise: LetterExercise(
        id: 'reach',
        title: 'Reach',
        steps: [letterExercise.steps.first, next],
      ),
      speech: SpeechCoordinator(audio),
    );
    await other.initialize();
    other.start();
    audio.holdSpeech = true;
    for (var index = 0; index < 3; index++) {
      other.typeCharacter('f');
    }
    expect(other.state.phase, ExercisePhase.reading);
    other.announceMode(TypingMode.advanced);
    audio.finishSpeech();
    await settle();
    expect(other.state.phase, ExercisePhase.typing);
    expect(audio.spoken.last, next.audio('instruction'));
    other.dispose();
  });

  test('wrong feedback names the actual key and repeats the current retry instruction', () async {
    await controller.initialize();
    controller.start();
    await settle();
    audio.spoken.clear();
    controller.typeCharacter('g');
    await settle();
    expect(audio.spoken, [
      AudioCues.wrongKeyPrefix,
      AudioCues.letter('g'),
      AudioCues.wrongKeySuffix,
      controller.step.audio('retry'),
    ]);
    expect(controller.state.successes, 0);
    expect(audio.feedbackResults, [false]);
  });

  test(
    'three fast successes interrupt earlier coaching and complete just once',
    () async {
      await controller.initialize();
      controller.start();
      audio.holdSpeech = true;
      controller.typeCharacter('f');
      controller.typeCharacter('g');
      controller.typeCharacter('F');
      controller.typeCharacter('f');
      expect(controller.state.phase, ExercisePhase.complete);
      expect(controller.state.successes, 3);
      expect(audio.spoken.last, controller.step.audio('complete'));
      audio.finishSpeech();
      await settle();
      expect(audio.spoken.last, AudioCues.complete);
      expect(
        audio.spoken.where((asset) => asset == controller.step.audio('retry')),
        isEmpty,
      );
    },
  );

  test(
    'leaving mid-feedback cancels the retry without shutting down shared audio',
    () async {
      final other = LetterTeachingController(
        exercise: letterExercise,
        speech: SpeechCoordinator(audio),
      );
      await other.initialize();
      other.start();
      audio.holdSpeech = true;
      other.typeCharacter('g');
      other.dispose();
      await settle();
      expect(audio.spoken.last, AudioCues.wrongKeyPrefix);
      expect(audio.disposed, isFalse);
    },
  );
}
