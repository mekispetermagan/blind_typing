import 'dart:convert';
import 'dart:io';

import 'package:blind_typing/controllers/typing_controller.dart';
import 'package:blind_typing/models/exercise.dart';
import 'package:blind_typing/models/practice_result.dart';
import 'package:blind_typing/services/exercise_scoring.dart';
import 'package:blind_typing/services/practice_records.dart';
import 'package:blind_typing/services/speech_coordinator.dart';

import 'support/fake_audio_service.dart';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('challenge content supplies 24 words and the agreed baselines', () {
    final settings = {'easy': 120, 'medium': 180, 'hard': 180, 'insane': 240};
    for (final MapEntry(key: name, value: seconds) in settings.entries) {
      final json = jsonDecode(
        File('../backend/data/practice/challenge_$name.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final exercise = TypingExercise.fromJson(json);
      expect(exercise.units, hasLength(24));
      expect(exercise.baselineSeconds, seconds);
      expect(
        ExerciseScoring(baselineSeconds: seconds)
            .score(seconds: seconds, mistakes: 10),
        100,
      );
      expect(
        ExerciseScoring(baselineSeconds: seconds)
            .score(seconds: seconds * 2, mistakes: 10),
        50,
      );
    }
    expect(const ExerciseScoring().score(seconds: 180, mistakes: 0), 167);
    expect(const ExerciseScoring().score(seconds: 0, mistakes: 10), 18000);
  });

  test('each challenge uses its baseline when completed', () async {
    for (final name in ['easy', 'medium', 'hard', 'insane']) {
      final json = jsonDecode(
        File('../backend/data/practice/challenge_$name.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      final exercise = TypingExercise.fromJson(json);
      final controller = TypingController(
        exercise: exercise,
        speech: SpeechCoordinator(FakeAudioService()),
      );
      await controller.initialize();
      controller.start();
      for (final unit in exercise.units) {
        for (final character in unit.text.split('')) {
          controller.typeCharacter(character);
        }
      }
      final result = controller.practiceResult!;
      expect(result.errors, 0);
      expect(
        result.score,
        ExerciseScoring(baselineSeconds: exercise.baselineSeconds)
            .score(seconds: result.seconds, mistakes: 0),
      );
      expect(result.highScore, result.score);
      controller.dispose();
    }
  });

  test(
    'removes legacy sample records and keeps challenge modes separate',
    () async {
      String? saved = jsonEncode({
        'words:sample_practice:simple': [180, 10, 100],
        'words:sample_practice:advanced': [120, 5, 200],
        'words:other:simple': [100, 3, 300],
      });
      final records = PracticeRecords(
        read: () async => saved,
        write: (value) async {
          saved = value;
        },
      );
      await records.load();
      await Future<void>.delayed(Duration.zero);
      expect(jsonDecode(saved!), {
        'words:other:simple': [100, 3, 300],
      });
      PracticeResult finish(TypingMode mode, int seconds) => records.finish(
        'challenge_easy',
        PracticeResult(seconds: seconds, errors: 10, mode: mode),
        scoring: const ExerciseScoring(baselineSeconds: 120),
      );
      expect(finish(TypingMode.simple, 120).highScore, 100);
      expect(finish(TypingMode.advanced, 240).highScore, 50);
      expect(finish(TypingMode.simple, 240).highScore, 100);
      await Future<void>.delayed(Duration.zero);
      final data = jsonDecode(saved!) as Map<String, dynamic>;
      expect(data['words:challenge_easy:simple'][2], 100);
      expect(data['words:challenge_easy:advanced'][2], 50);
    },
  );
}
