import 'dart:convert';

import 'package:blind_typing/controllers/typing_controller.dart';
import 'package:blind_typing/managers/practice_attempt.dart';
import 'package:blind_typing/models/exercise.dart';
import 'package:blind_typing/models/practice_result.dart';
import 'package:blind_typing/models/typing_unit.dart';
import 'package:blind_typing/services/audio_service.dart';
import 'package:blind_typing/services/practice_feedback.dart';
import 'package:blind_typing/services/practice_records.dart';
import 'package:blind_typing/services/speech_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio_service.dart';

class _ManualStopwatch extends Fake implements Stopwatch {
  bool _running = false;
  @override
  Duration elapsed = Duration.zero;

  @override
  void start() => _running = true;

  @override
  void stop() => _running = false;

  void advance(Duration duration) {
    if (_running) elapsed += duration;
  }
}

void main() {
  test('an attempt accumulates time only while accepting input', () {
    final timer = _ManualStopwatch();
    final attempt = PracticeAttempt(timer: timer);
    timer.advance(const Duration(seconds: 10));
    attempt.setAcceptingInput(true);
    timer.advance(const Duration(seconds: 60));
    attempt.recordError();
    attempt.setAcceptingInput(false);
    timer.advance(const Duration(seconds: 10));
    attempt.setAcceptingInput(true);
    timer.advance(const Duration(seconds: 23));
    final result = attempt.finish();
    timer.advance(const Duration(seconds: 10));

    expect(result.seconds, 83);
    expect(result.errors, 1);
    expect(timer.elapsed.inSeconds, 83);
  });

  test(
    'records persist independent improvements by activity and mode',
    () async {
      String? saved;
      PracticeRecords store() => PracticeRecords(
        read: () async => saved,
        write: (value) async {
          saved = value;
        },
      );

      final records = store();
      await records.load();
      PracticeResult finish(
        int seconds,
        int errors, {
        String id = 'drill',
        TypingMode? mode = TypingMode.simple,
        bool changedMode = false,
      }) => records.finish(
        id,
        PracticeResult(
          seconds: seconds,
          errors: errors,
          mode: mode,
          changedMode: changedMode,
        ),
      );

      expect(finish(10, 5).bestTime, isFalse);
      final faster = finish(8, 7);
      expect(faster.bestTime, isTrue);
      expect(faster.fewestErrors, isFalse);
      final fewer = finish(9, 3);
      expect(fewer.bestTime, isFalse);
      expect(fewer.fewestErrors, isTrue);
      final tie = finish(8, 3);
      expect(tie.bestTime, isFalse);
      expect(tie.fewestErrors, isFalse);
      expect(finish(1, 0, changedMode: true).bestTime, isFalse);
      expect(finish(15, 6, mode: TypingMode.advanced).bestTime, isFalse);
      expect(finish(18, 2, id: 'other').fewestErrors, isFalse);
      expect(finish(1, 1, mode: null).fewestErrors, isFalse);

      await Future<void>.delayed(Duration.zero);
      expect(jsonDecode(saved!), {
        'words:drill:simple': [8, 3],
        'words:drill:advanced': [15, 6],
        'words:other:simple': [18, 2],
        'letters:drill': [1, 1],
      });
      final reopened = store();
      await reopened.load();
      final result = reopened.finish(
        'drill',
        const PracticeResult(seconds: 14, errors: 5, mode: TypingMode.advanced),
      );
      expect(result.bestTime, isTrue);
      expect(result.fewestErrors, isTrue);
    },
  );

  test(
    'advanced corrections count and a mode change while paused counts too',
    () async {
      final audio = FakeAudioService();
      final controller = TypingController(
        exercise: TypingExercise(
          id: 'short_drill',
          title: 'Short drill',
          type: ActivityType.words,
          allowedLetters: 'AF',
          units: [TypingUnit(id: 'short_target', text: 'AF')],
        ),
        speech: SpeechCoordinator(audio),
      );
      addTearDown(controller.dispose);
      await controller.initialize();

      controller.toggleMode();
      controller.start();
      controller.typeCharacter(' ');
      controller.typeCharacter('x');
      controller.typeCharacter('a');
      controller.backspace();
      controller.backspace();
      controller.typeCharacter('a');
      controller.typeCharacter('f');
      await Future<void>.delayed(Duration.zero);

      final advanced = controller.practiceResult!;
      expect(advanced.mode, TypingMode.advanced);
      expect(advanced.errors, 2);
      expect(advanced.changedMode, isFalse);
      expect(
        audio.spoken,
        containsAllInOrder([
          AudioCues.modeAdvanced,
          'assets/audio/result_time.wav',
          'assets/audio/result_errors.wav',
          AudioCues.count(2),
          AudioCues.complete,
        ]),
      );

      controller.start();
      expect(controller.practiceResult, isNull);
      controller.pause();
      controller.typeCharacter('x');
      controller.toggleMode();
      controller.toggleMode();
      controller.togglePause();
      controller.typeCharacter('a');
      controller.typeCharacter('f');
      final mixed = controller.practiceResult!;
      expect(mixed.errors, 0);
      expect(mixed.changedMode, isTrue);
      expect(mixed.fewestErrors, isFalse);
    },
  );

  test('feedback names the mode and uses the right forms of two', () {
    const result = PracticeResult(
      seconds: 132,
      errors: 2,
      mode: TypingMode.simple,
      bestTime: true,
    );
    expect(
      PracticeFeedback.describe(result),
      'Egyszerű mód. Az időd 2 perc 12 másodperc. '
      'A hibás leütések száma 2. Ez eddig a legjobb időd.',
    );
    expect(PracticeFeedback.speech(result), [
      AudioCues.modeSimple,
      'assets/audio/result_time.wav',
      'assets/audio/result_number_2_before_unit.wav',
      'assets/audio/result_minute.wav',
      'assets/audio/result_number_12_before_unit.wav',
      'assets/audio/result_second.wav',
      'assets/audio/result_errors.wav',
      AudioCues.count(2),
      'assets/audio/result_best_time.wav',
    ]);
  });
}
