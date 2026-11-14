import 'package:blind_typing/controllers/letter_teaching_controller.dart';
import 'package:blind_typing/controllers/typing_controller.dart';
import 'package:blind_typing/models/exercise.dart';
import 'package:blind_typing/models/typing_unit.dart';
import 'package:blind_typing/services/speech_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio_service.dart';

void main() {
  test(
    'advanced errors count separately from first-try targets and backspacing',
    () async {
      final snapshots = <Map<String, dynamic>>[];
      final controller = TypingController(
        exercise: TypingExercise(
          id: 'test',
          title: 'test',
          type: ActivityType.words,
          allowedLetters: 'AB',
          units: [TypingUnit(id: 'w', text: 'AB')],
        ),
        mode: TypingMode.advanced,
        speech: SpeechCoordinator(FakeAudioService()),
        onAttempt: snapshots.add,
      );
      await controller.initialize();
      controller.start();
      controller.typeCharacter('x');
      controller.typeCharacter('y');
      controller.backspace();
      controller.backspace();
      controller.typeCharacter('a');
      controller.backspace();
      controller.typeCharacter('a');
      controller.typeCharacter('b');
      final last = snapshots.last;
      expect(last['status'], 'completed');
      expect(last['mistake_count'], 2);
      expect(last['keys']['a'], {
        'first_try_correct_count': 0,
        'first_try_incorrect_count': 1,
      });
      expect(last['keys']['b'], {
        'first_try_correct_count': 1,
        'first_try_incorrect_count': 0,
      });
      controller.dispose();
    },
  );

  test(
    'teaching retries count each target once and restart interrupts',
    () async {
      final snapshots = <Map<String, dynamic>>[];
      final controller = LetterTeachingController(
        exercise: LetterExercise(
          id: 'lesson',
          title: 'lesson',
          steps: [
            LetterStep(
              id: 'step',
              key: 'Ö',
              instruction: '',
              retry: '',
              success: '',
              complete: '',
              requiredSuccesses: 2,
            ),
          ],
        ),
        speech: SpeechCoordinator(FakeAudioService()),
        onAttempt: snapshots.add,
      );
      await controller.initialize();
      controller.start();
      controller.typeCharacter('a');
      controller.typeCharacter('a');
      controller.typeCharacter('ö');
      controller.typeCharacter('ö');
      final last = snapshots.last;
      expect(last['status'], 'completed');
      expect(last['mistake_count'], 2);
      expect(last['keys']['ö'], {
        'first_try_correct_count': 1,
        'first_try_incorrect_count': 1,
      });
      controller.start();
      controller.pause();
      controller.start();
      expect(snapshots[snapshots.length - 2]['status'], 'interrupted');
      controller.dispose();
    },
  );
}
