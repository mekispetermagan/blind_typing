import 'package:blind_typing/controllers/typing_controller.dart';
import 'package:blind_typing/models/exercise.dart';
import 'package:blind_typing/models/typing_unit.dart';
import 'package:blind_typing/services/audio_service.dart';
import 'package:blind_typing/services/speech_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio_service.dart';

TypingExercise drill(String text, {PromptStyle style = PromptStyle.word}) =>
    TypingExercise(
      id: 'prompt_test',
      title: 'Prompt test',
      type: ActivityType.words,
      allowedLetters: text,
      units: [TypingUnit(id: 'target', text: text, promptStyle: style)],
    );

void main() {
  testWidgets(
    'initial prompt and F1 spell after speech and a one-second pause',
    (tester) async {
      final audio = FakeAudioService();
      final controller = TypingController(
        exercise: drill('AB'),
        speech: SpeechCoordinator(audio),
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      audio.spoken.clear();
      audio.holdSpeech = true;
      controller.start();
      await tester.pump(const Duration(seconds: 2));
      expect(audio.spoken, ['assets/audio/target_word_0.wav']);
      audio.holdSpeech = false;
      audio.finishSpeech();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 999));
      expect(audio.spoken, ['assets/audio/target_word_0.wav']);
      await tester.pump(const Duration(milliseconds: 1));
      expect(audio.spoken.last, AudioCues.letter('a'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(audio.spoken.last, AudioCues.letter('b'));

      audio.spoken.clear();
      controller.repeatWord();
      await tester.pump();
      expect(audio.spoken, ['assets/audio/target_word_0.wav']);
      await tester.pump(const Duration(seconds: 1));
      expect(audio.spoken.last, AudioCues.letter('a'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(audio.spoken.last, AudioCues.letter('b'));
    },
  );

  testWidgets(
    'input interrupts the pause and F2 spells only entered characters',
    (tester) async {
      final audio = FakeAudioService();
      final controller = TypingController(
        exercise: drill('AB'),
        speech: SpeechCoordinator(audio),
        mode: TypingMode.advanced,
      );
      addTearDown(controller.dispose);
      await controller.initialize();
      audio.spoken.clear();
      controller.start();
      await tester.pump();
      controller.typeCharacter('a');
      await tester.pump(const Duration(seconds: 1));
      expect(audio.spoken, ['assets/audio/target_word_0.wav']);
      controller.typeCharacter('x');
      controller.spellEnteredLetters();
      await tester.pump();
      expect(audio.spoken.last, AudioCues.letter('a'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(audio.spoken.last, AudioCues.letter('x'));
    },
  );

  testWidgets('the next number is read and then spelled', (tester) async {
    final audio = FakeAudioService();
    final exercise = TypingExercise(
      id: 'number_prompt_test',
      title: 'Number prompt test',
      type: ActivityType.words,
      allowedLetters: '1234',
      units: [
        TypingUnit(id: 'first_number', text: '12'),
        TypingUnit(id: 'next_number', text: '34'),
      ],
    );
    final controller = TypingController(
      exercise: exercise,
      speech: SpeechCoordinator(audio),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    controller.start();
    controller.typeCharacter('1');
    controller.typeCharacter('2');
    await tester.pump();
    expect(audio.spoken.last, 'assets/audio/next_number_word_0.wav');
    await tester.pump(const Duration(seconds: 1));
    expect(audio.spoken.last, AudioCues.count(3));
    await tester.pump(const Duration(milliseconds: 250));
    expect(audio.spoken.last, 'assets/audio/result_number_4.wav');
  });

  testWidgets('letter-by-letter prompts keep their existing timing', (
    tester,
  ) async {
    final audio = FakeAudioService();
    final controller = TypingController(
      exercise: drill('AB', style: PromptStyle.letters),
      speech: SpeechCoordinator(audio),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    audio.spoken.clear();
    controller.start();
    await tester.pump();
    expect(audio.spoken, [AudioCues.letter('a')]);
    await tester.pump(const Duration(milliseconds: 250));
    expect(audio.spoken, [AudioCues.letter('a'), AudioCues.letter('b')]);
    await tester.pump(const Duration(seconds: 1));
    expect(audio.spoken, hasLength(2));
    controller.repeatWord();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(audio.spoken, [
      AudioCues.letter('a'),
      AudioCues.letter('b'),
      AudioCues.letter('a'),
      AudioCues.letter('b'),
    ]);
  });
}
