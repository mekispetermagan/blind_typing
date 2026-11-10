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

  group('spelling the accepted prefix', () {
    setUp(() {
      controller.dispose();
      audio = FakeAudioService();
      controller = TypingController(
        sentences: [Sentence(id: 'spelling', text: 'Pillangó árvíztűrő')],
        audio: audio,
        countdownInterval: Duration.zero,
      );
    });

    Future<void> enterPrefix(WidgetTester tester, String prefix) async {
      await controller.initialize();
      controller.start();
      await tester.pump();
      for (final letter in prefix.split('')) {
        controller.typeCharacter(letter);
      }
      await tester.pump();
      audio.spoken.clear();
    }

    test('ignores an empty prefix and phases outside typing', () async {
      await controller.initialize();
      expect(
        audio.loaded,
        containsAll([
          for (final letter in AudioCues.alphabet.split(''))
            AudioCues.letter(letter),
        ]),
      );
      final readySpeech = List<String>.of(audio.spoken);
      controller.spellEnteredLetters();
      expect(audio.spoken, readySpeech);
      controller.start();
      final readingSpeech = List<String>.of(audio.spoken);
      controller.spellEnteredLetters();
      expect(audio.spoken, readingSpeech);
      await settle();
      final typingSpeech = List<String>.of(audio.spoken);
      controller.spellEnteredLetters();
      expect(audio.spoken, typingSpeech);
      controller.typeCharacter('p');
      controller.pause();
      final pausedSpeech = List<String>.of(audio.spoken);
      controller.spellEnteredLetters();
      expect(audio.spoken, pausedSpeech);
    });

    testWidgets(
      'spells pillang in order with 250 ms gaps, preserving progress',
      (tester) async {
        await enterPrefix(tester, 'pillang');
        final feedbackCount = audio.feedbackResults.length;
        controller.spellEnteredLetters();
        final letters = 'pillang'.split('');
        for (var index = 0; index < letters.length; index++) {
          expect(audio.spoken, letters.take(index + 1).map(AudioCues.letter));
          await tester.pump();
          if (index + 1 < letters.length) {
            await tester.pump(const Duration(milliseconds: 249));
            expect(audio.spoken, hasLength(index + 1));
            await tester.pump(const Duration(milliseconds: 1));
          }
        }
        expect(controller.letterIndex, 7);
        expect(controller.wordIndex, 0);
        expect(controller.phase, ExercisePhase.typing);
        expect(audio.feedbackResults, hasLength(feedbackCount));
      },
    );

    testWidgets('uses the current word and preserves accented letters', (
      tester,
    ) async {
      await enterPrefix(tester, 'pillangóárvíztűr');
      controller.spellEnteredLetters();
      await tester.pump();
      for (var index = 1; index < 'árvíztűr'.length; index++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      expect(audio.spoken, 'árvíztűr'.split('').map(AudioCues.letter));
      expect(controller.wordIndex, 1);
      expect(controller.letterIndex, 8);
    });

    testWidgets(
      'a wrong character interrupts active spelling and stays wrong',
      (tester) async {
        await enterPrefix(tester, 'pill');
        audio.holdSpeech = true;
        controller.spellEnteredLetters();
        controller.typeCharacter('x');
        await tester.pump(const Duration(seconds: 1));
        expect(audio.interrupted, [AudioCues.letter('p')]);
        expect(audio.spoken, [AudioCues.letter('p')]);
        expect(controller.letterIndex, 4);
        expect(audio.feedbackResults.last, isFalse);
        expect(controller.phase, ExercisePhase.typing);
      },
    );

    testWidgets('cancels during a gap and restarts without stale letters', (
      tester,
    ) async {
      await enterPrefix(tester, 'pill');
      controller.spellEnteredLetters();
      await tester.pump();
      controller.cancelSpelling();
      await tester.pump(const Duration(seconds: 1));
      expect(audio.spoken, [AudioCues.letter('p')]);
      controller.spellEnteredLetters();
      await tester.pump();
      controller.spellEnteredLetters();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(audio.spoken, [
        AudioCues.letter('p'),
        AudioCues.letter('p'),
        AudioCues.letter('p'),
        AudioCues.letter('i'),
      ]);
      controller.cancelSpelling();
      await tester.pump(const Duration(milliseconds: 250));
      expect(audio.spoken, hasLength(4));
    });

    for (final action in ['repeat', 'pause', 'complete word']) {
      testWidgets('$action replaces spelling without later stale playback', (
        tester,
      ) async {
        await enterPrefix(tester, 'pillang');
        controller.spellEnteredLetters();
        await tester.pump();
        switch (action) {
          case 'repeat':
            controller.repeatWord();
          case 'pause':
            controller.pause();
          case 'complete word':
            controller.typeCharacter('ó');
        }
        await tester.pump();
        final spoken = List<String>.of(audio.spoken);
        await tester.pump(const Duration(seconds: 1));
        expect(audio.spoken, spoken);
        expect(audio.spoken.last, switch (action) {
          'pause' => AudioCues.paused,
          'complete word' => controller.sentence.wordAudioAsset(1),
          _ => controller.sentence.wordAudioAsset(0),
        });
      });
    }

    testWidgets('playback failure enters the recoverable error state', (
      tester,
    ) async {
      await enterPrefix(tester, 'pill');
      audio.failSpeech = true;
      controller.spellEnteredLetters();
      await tester.pump();
      expect(controller.phase, ExercisePhase.error);
    });

    testWidgets('disposing during spelling cancels remaining letters', (
      tester,
    ) async {
      final otherAudio = FakeAudioService();
      final other = TypingController(
        sentences: sampleSentences,
        audio: otherAudio,
        countdownInterval: Duration.zero,
      );
      await other.initialize();
      other.start();
      await tester.pump();
      other.typeCharacter('a');
      other.typeCharacter('n');
      otherAudio.holdSpeech = true;
      other.spellEnteredLetters();
      other.dispose();
      await tester.pump(const Duration(seconds: 1));
      expect(otherAudio.disposed, isTrue);
      expect(otherAudio.spoken.where((asset) => asset.contains('letter_')), [
        AudioCues.letter('a'),
      ]);
    });
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
