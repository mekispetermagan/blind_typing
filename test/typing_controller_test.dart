import 'package:blind_typing/controllers/typing_controller.dart';
import 'package:blind_typing/models/sentence.dart';
import 'package:blind_typing/services/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio_service.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeAudioService audio;
  late TypingController controller;

  setUp(() {
    audio = FakeAudioService();
    controller = TypingController(
      sentences: sampleSentences,
      audio: audio,
      countdownInterval: Duration.zero,
    );
  });
  tearDown(() => controller.dispose());

  test('reads sentence, counts down, then speaks first word', () async {
    await controller.initialize();
    expect(controller.phase, ExercisePhase.ready);
    expect(audio.loaded, containsAll(sampleSentences.first.audioAssets));
    controller.start();
    controller.typeCharacter('a');
    expect(audio.feedbackResults, isEmpty);
    await settle();
    expect(controller.phase, ExercisePhase.typing);
    expect(audio.spoken, [
      AudioCues.welcome,
      sampleSentences.first.audioAsset,
      AudioCues.count(3),
      AudioCues.count(2),
      AudioCues.count(1),
      sampleSentences.first.wordAudioAsset(0),
    ]);
  });

  test(
    'rejects errors, ignores spaces and case, requires exact accents',
    () async {
      await controller.initialize();
      controller.start();
      await settle();
      controller.typeCharacter('x');
      controller.typeCharacter(' ');
      expect(controller.letterIndex, 0);
      expect(audio.feedbackResults, [false]);
      expect(audio.celebrations, isEmpty);
      for (final letter in 'aNNa'.split('')) {
        controller.typeCharacter(letter);
      }
      expect(controller.wordIndex, 1);
      expect(controller.letterIndex, 0);
      controller.typeCharacter(' ');
      controller.typeCharacter('A');
      controller.typeCharacter('L');
      controller.typeCharacter('M');
      controller.typeCharacter('a');
      expect(controller.letterIndex, 3);
      expect(audio.feedbackResults.last, isFalse);
      controller.typeCharacter('Á');
      expect(controller.letterIndex, 4);
      controller.typeCharacter('t');
      expect(controller.wordIndex, 2);
    },
  );

  test(
    'word celebration interrupts speech without blocking fast typing',
    () async {
      await controller.initialize();
      controller.start();
      await settle();
      audio.holdSpeech = true;
      controller.repeatWord();
      for (final letter in 'Anna'.split('')) {
        controller.typeCharacter(letter);
      }
      expect(controller.wordIndex, 1);
      expect(audio.interrupted.last, sampleSentences.first.wordAudioAsset(0));
      expect(audio.celebrations, [false]);
      controller.typeCharacter('a');
      expect(controller.letterIndex, 1);
      audio.finishSpeech();
      await settle();
      expect(audio.spoken.last, sampleSentences.first.wordAudioAsset(1));
      controller.repeatWord();
      expect(controller.letterIndex, 1);
    },
  );

  test('fast word completion cancels stale delayed word prompts', () async {
    await controller.initialize();
    controller.start();
    await settle();
    audio.holdSpeech = true;
    for (final letter in 'Annaalmát'.split('')) {
      controller.typeCharacter(letter);
    }
    expect(controller.wordIndex, 2);
    expect(audio.celebrations, [false, false]);
    audio.finishSpeech();
    await settle();
    expect(
      audio.spoken,
      isNot(contains(sampleSentences.first.wordAudioAsset(1))),
    );
    expect(audio.spoken.last, sampleSentences.first.wordAudioAsset(2));
  });

  test(
    'repeat during a reward does not replay a stale prompt afterwards',
    () async {
      await controller.initialize();
      controller.start();
      await settle();
      audio.holdSpeech = true;
      for (final letter in 'Anna'.split('')) {
        controller.typeCharacter(letter);
      }
      controller.repeatWord();
      await settle();
      expect(
        audio.spoken.where(
          (asset) => asset == sampleSentences.first.wordAudioAsset(1),
        ),
        hasLength(1),
      );
    },
  );

  test(
    'pause ignores input; resume and repeat preserve accepted letters',
    () async {
      await controller.initialize();
      controller.start();
      await settle();
      controller.typeCharacter('a');
      controller.togglePause();
      expect(controller.phase, ExercisePhase.paused);
      controller.typeCharacter('n');
      expect(controller.letterIndex, 1);
      controller.togglePause();
      expect(controller.phase, ExercisePhase.typing);
      expect(controller.letterIndex, 1);
      expect(audio.spoken.last, sampleSentences.first.wordAudioAsset(0));
    },
  );

  test(
    'pausing instructions prevents stale completion from starting countdown',
    () async {
      await controller.initialize();
      audio.holdSpeech = true;
      controller.start();
      expect(controller.phase, ExercisePhase.reading);
      controller.pause();
      await settle();
      expect(controller.phase, ExercisePhase.paused);
      audio.finishSpeech();
      await settle();
      expect(controller.phase, ExercisePhase.paused);
      controller.togglePause();
      expect(controller.phase, ExercisePhase.reading);
      expect(audio.spoken.last, sampleSentences.first.audioAsset);
    },
  );

  test('ignores countdown typing and cancels interrupted countdown', () async {
    await controller.initialize();
    audio.holdSpeech = true;
    controller.start();
    audio.finishSpeech();
    await settle();
    expect(controller.phase, ExercisePhase.countdown);
    expect(controller.countdown, 3);
    controller.typeCharacter('a');
    expect(audio.feedbackResults, isEmpty);
    controller.pause();
    await settle();
    expect(controller.phase, ExercisePhase.paused);
    controller.togglePause();
    expect(controller.phase, ExercisePhase.reading);
    expect(controller.countdown, isNull);
  });

  test(
    'all five sentences advance automatically and Enter can restart',
    () async {
      await controller.initialize();
      controller.start();
      await settle();
      for (var index = 0; index < sampleSentences.length; index++) {
        expect(controller.sentenceIndex, index);
        for (final letter in sampleSentences[index].text.split('')) {
          controller.typeCharacter(letter);
        }
        await settle();
      }
      expect(controller.phase, ExercisePhase.complete);
      expect(audio.spoken.last, AudioCues.complete);
      expect(audio.feedbackResults.every((correct) => correct), isTrue);
      expect(
        audio.celebrations,
        hasLength(
          sampleSentences.fold<int>(
            0,
            (total, sentence) => total + sentence.words.length,
          ),
        ),
      );
      expect(audio.celebrations.where((sentence) => sentence), hasLength(5));
      controller.start();
      await settle();
      expect(controller.sentenceIndex, 0);
      expect(controller.wordIndex, 0);
      expect(controller.letterIndex, 0);
      expect(controller.phase, ExercisePhase.typing);
    },
  );

  test('playback failure enters recoverable error state', () async {
    await controller.initialize();
    controller.start();
    await settle();
    audio.failSpeech = true;
    controller.repeatWord();
    expect(controller.phase, ExercisePhase.error);
    audio.failSpeech = false;
    controller.start();
    await settle();
    expect(controller.phase, ExercisePhase.ready);
  });

  test(
    'disposing during pending speech invalidates pending progression',
    () async {
      final otherAudio = FakeAudioService();
      final other = TypingController(
        sentences: sampleSentences,
        audio: otherAudio,
        countdownInterval: Duration.zero,
      );
      await other.initialize();
      otherAudio.holdSpeech = true;
      other.start();
      other.dispose();
      await settle();
      expect(otherAudio.disposed, isTrue);
      expect(
        otherAudio.spoken.where((asset) => asset.contains('count_')),
        isEmpty,
      );
    },
  );
}
