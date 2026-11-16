import 'dart:async';
import 'dart:io';

import 'package:blind_typing/api/progress_repository.dart';
import 'package:blind_typing/api/trainer_repository.dart';
import 'package:blind_typing/models/progress_navigation.dart';
import 'package:blind_typing/screens/progress_screen.dart';
import 'package:blind_typing/services/audio_service.dart';
import 'package:blind_typing/services/speech_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio_service.dart';

class FailingProgressAudio extends FakeAudioService {
  @override
  Future<void> initialize(Iterable<String> assets) async {
    final list = assets.toList();
    if (list.contains('assets/audio/progress_help.wav')) {
      throw StateError('audio backend unavailable');
    }
    await super.initialize(list);
  }
}

StudentProgress sampleProgress() => StudentProgress(
  name: 'Test',
  attempts: [
    ProgressAttempt(
      activityId: 'sample',
      title: 'Ö gyakorlás',
      startedAt: DateTime(2026, 11, 12),
      status: 'completed',
      activeDurationMs: 120000,
      mistakeCount: 3,
      keys: [const KeyProgress(key: 'ö', correct: 3, incorrect: 1)],
    ),
  ],
);

void main() {
  test('cardinal dates use existing number clips and each item has its audio asset', () {
    final nav = ProgressNavigation(sampleProgress(), DateTime(2026, 11, 12), {
      'sample': ['assets/audio/menu_my_progress.wav'],
    });
    expect(nav.sections.first.title, 'Az elmúlt 7 napban');
    expect(nav.sections[1].items.length, 15); // Seven days plus eight weeks.
    expect(nav.sections[1].items[7].title, '2026.11.06 – 2026.11.12');
    expect(nav.sections[1].items[8].title, '2026.10.30 – 2026.11.05');
    final thursdayItem = nav.sections[1].items[6];
    expect(
      thursdayItem.subtitle,
      'Befejezett: 1 · Megszakított: 0\nAktív gyakorlási idő: 2 perc',
    );
    final thursday = thursdayItem.audio;
    expect(
      thursday,
      containsAllInOrder([
        'assets/audio/progress_day_4.wav',
        'assets/audio/result_number_2_before_unit.wav',
        'assets/audio/result_thousand.wav',
        'assets/audio/result_number_26.wav',
        'assets/audio/progress_month_11.wav',
        'assets/audio/result_number_12.wav',
        'assets/audio/progress_duration.wav',
        'assets/audio/result_number_2_before_unit.wav',
        'assets/audio/result_minute.wav',
      ]),
    );
    for (final asset in nav.allAudio) {
      expect(File('../backend/$asset').existsSync(), isTrue, reason: asset);
    }
    expect(File('assets/audio/progress_loading.wav').existsSync(), isTrue);
    expect(File('assets/audio/progress_failure.wav').existsSync(), isTrue);
  });

  testWidgets(
    'trainer progress announces student and returns to the selector',
    (tester) async {
      final audio = FakeAudioService();
      var returned = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ProgressScreen(
            student: const TrainerStudent(
              id: 1,
              name: 'Péter',
              nameAudioRevision: '0123456789abcdef',
            ),
            loadProgress: () async => sampleProgress(),
            speech: SpeechCoordinator(audio),
            onBack: () => returned = true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Péter – Haladás'), findsOneWidget);
      expect(
        audio.spoken,
        contains('assets/audio/student_name_1_0123456789abcdef.wav'),
      );
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
      }
      expect(audio.spoken.last, 'assets/audio/progress_return_students.wav');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(returned, isTrue);
    },
  );

  test(
    'progress exposes every homework submission, not only ten recent attempts',
    () {
      final progress = StudentProgress(
        name: 'Teszt',
        attempts: [
          for (var i = 0; i < 13; i++)
            ProgressAttempt(
              activityId: 'homework_123',
              title: 'Házi feladat $i',
              startedAt: DateTime(2026, 11, 12),
              status: 'completed',
              activeDurationMs: 1000,
              mistakeCount: 0,
              keys: const [],
            ),
        ],
      );
      final navigation = ProgressNavigation(
        progress,
        DateTime(2026, 11, 12),
        {},
      );
      final homeworks = navigation.sections.firstWhere(
        (section) => section.title == 'Házi feladatok',
      );
      expect(homeworks.items.length, 13);
      expect(navigation.sections.last.title, 'Vissza a főmenübe');
    },
  );

  test('daily and weekly times truncate after summing, including speech', () {
    final progress = StudentProgress(
      name: 'Test',
      attempts: [
        ProgressAttempt(
          title: 'First',
          startedAt: DateTime(2026, 11, 11),
          status: 'completed',
          activeDurationMs: 59000,
          mistakeCount: 0,
          keys: const [],
        ),
        ProgressAttempt(
          title: 'Second',
          startedAt: DateTime(2026, 11, 12),
          status: 'completed',
          activeDurationMs: 31000,
          mistakeCount: 0,
          keys: const [],
        ),
      ],
    );
    final nav = ProgressNavigation(progress, DateTime(2026, 11, 12), {});
    final weekly = nav.sections[0].items[1];
    expect(weekly.title, 'Aktív gyakorlási idő: 1 perc');
    expect(weekly.audio.last, 'assets/audio/result_minute.wav');
    expect(weekly.audio, isNot(contains('assets/audio/result_second.wav')));
    for (final day in nav.sections[1].items.sublist(5, 7)) {
      expect(day.subtitle, contains('Aktív gyakorlási idő: 0 perc'));
      expect(day.audio.last, 'assets/audio/result_minute.wav');
      expect(day.audio, isNot(contains('assets/audio/result_second.wav')));
    }
    final recent = nav.sections[3].items.first;
    expect(recent.subtitle, contains('0 perc 59 másodperc'));
    expect(recent.audio, contains('assets/audio/result_second.wav'));
  });

  testWidgets('arrows, Home, End and F1 speak items while skipping charts', (
    tester,
  ) async {
    final audio = FakeAudioService();
    var wentBack = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ProgressScreen(
          loadProgress: () async => sampleProgress(),
          speech: SpeechCoordinator(audio),
          activityAudio: const {
            'sample': ['assets/audio/menu_my_progress.wav'],
          },
          onBack: () => wentBack = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      audio.loaded,
      containsAll([AudioCues.progressLoading, AudioCues.progressFailure]),
    );
    expect(audio.spoken, contains('assets/audio/progress_help.wav'));
    Future<void> key(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    audio.spoken.clear();
    await key(LogicalKeyboardKey.arrowRight);
    expect(
      audio.spoken,
      contains('assets/audio/progress_section_activity.wav'),
    );
    final now = DateTime.now();
    final firstDay = DateTime(now.year, now.month, now.day - 6).weekday;
    final secondDay = firstDay % 7 + 1;
    expect(audio.spoken, contains('assets/audio/progress_day_$firstDay.wav'));
    audio.spoken.clear();
    await key(LogicalKeyboardKey.arrowDown);
    expect(audio.spoken, contains('assets/audio/progress_day_$secondDay.wav'));
    audio.spoken.clear();
    await key(LogicalKeyboardKey.end);
    expect(audio.spoken, contains('assets/audio/progress_week.wav'));
    audio.spoken.clear();
    await key(LogicalKeyboardKey.home);
    expect(audio.spoken, contains('assets/audio/progress_day_$firstDay.wav'));
    audio.spoken.clear();
    await key(LogicalKeyboardKey.arrowRight);
    expect(audio.spoken, contains('assets/audio/letter_00f6.wav'));
    expect(audio.spoken, contains('assets/audio/progress_correct.wav'));
    audio.spoken.clear();
    await key(LogicalKeyboardKey.f1);
    expect(audio.spoken, contains('assets/audio/letter_00f6.wav'));
    audio.spoken.clear();
    await key(LogicalKeyboardKey.arrowRight);
    expect(audio.spoken, contains('assets/audio/menu_my_progress.wav'));
    audio.spoken.clear();
    audio.holdSpeech = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(audio.interrupted, isNotEmpty);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(wentBack, isTrue);
  });

  testWidgets('final progress section announces return and Enter goes back', (
    tester,
  ) async {
    final audio = FakeAudioService();
    var wentBack = false;
    await tester.pumpWidget(
      MaterialApp(
        home: ProgressScreen(
          speech: SpeechCoordinator(audio),
          loadProgress: () async => sampleProgress(),
          onBack: () => wentBack = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 4; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
    expect(audio.spoken.last, 'assets/audio/progress_return_main.wav');
    expect(find.text('Vissza a főmenübe'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(wentBack, isTrue);
  });

  testWidgets('missing backend audio announces the bundled failure', (
    tester,
  ) async {
    final audio = FailingProgressAudio();
    await tester.pumpWidget(
      MaterialApp(
        home: ProgressScreen(
          speech: SpeechCoordinator(audio),
          loadProgress: () async => sampleProgress(),
          onBack: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(audio.spoken.last, AudioCues.progressFailure);
    expect(
      find.textContaining('A haladási adatok nem tölthetők be.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'loading and failure are bundled, spoken, repeatable and retryable',
    (tester) async {
      final audio = FakeAudioService();
      final first = Completer<StudentProgress>();
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProgressScreen(
            speech: SpeechCoordinator(audio),
            loadProgress: () {
              calls++;
              return calls == 1 ? first.future : Future.value(sampleProgress());
            },
            onBack: () {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(audio.spoken, contains(AudioCues.progressLoading));
      first.completeError(StateError('offline'));
      await tester.pumpAndSettle();
      expect(audio.spoken.last, AudioCues.progressFailure);
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(audio.spoken.last, AudioCues.progressFailure);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('Betűstatisztika'), findsOneWidget);
      expect(audio.spoken, contains('assets/audio/progress_help.wav'));
    },
  );
}
