import 'package:blind_typing/api/homework_repository.dart';
import 'package:blind_typing/api/attempt_sync.dart';
import 'package:blind_typing/api/progress_repository.dart';
import 'package:blind_typing/managers/typing_session_manager.dart';
import 'package:blind_typing/models/exercise.dart';
import 'package:blind_typing/models/typing_state.dart';
import 'package:blind_typing/screens/homework_form_screen.dart';
import 'package:blind_typing/screens/homework_list_screen.dart';
import 'package:blind_typing/screens/homework_practice_screen.dart';
import 'package:blind_typing/services/practice_records.dart';
import 'package:blind_typing/services/exercise_scoring.dart';
import 'package:blind_typing/services/speech_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio_service.dart';

class FakeHomeworkRepository extends HomeworkRepository {
  List<HomeworkEntryData>? created;
  DateTime? deadline;
  HomeworkData? loaded;
  @override
  Future<HomeworkData> load(String id) async => loaded!;
  @override
  Future<void> create(
    int studentId,
    DateTime deadline,
    List<HomeworkEntryData> entries, {
    String? requestId,
  }) async {
    created = entries;
    this.deadline = deadline;
  }
}

void main() {
  test(
    'homework skips punctuation and spaces, types digits, scales baseline',
    () {
      final exercise = ExerciseDefinition.fromJson({
        'id': 'homework_123',
        'title': 'Házi feladat',
        'type': 'homework',
        'baselineSeconds': 22.5,
        'units': [
          {
            'id': 'one',
            'text': 'Alma, 12! körte.',
            'sentenceAudio': 'assets/audio/test.wav',
            'wordAudio': ['a', 'b', 'c'],
          },
        ],
      }) as TypingExercise;
      expect(exercise.units.single.words, ['Alma', '12', 'körte']);
      expect(exercise.baselineSeconds, 22.5);
      expect(
        const ExerciseScoring(baselineSeconds: 270)
            .score(seconds: 270, mistakes: 10),
        100,
      );
      final manager = TypingSessionManager(exercise);
      manager.ready();
      manager.restart();
      manager.beginTyping();
      TypingResult result = TypingResult.ignored;
      expect(manager.typeCharacter('!'), TypingResult.ignored);
      for (final character in 'alma12körte'.split('')) {
        result = manager.typeCharacter(character);
      }
      expect(result, TypingResult.completed);
    },
  );
  testWidgets('form adds editable rows and ignores final blank row', (
    tester,
  ) async {
    final audio = FakeAudioService();
    final repo = FakeHomeworkRepository();
    var saved = false;
    await tester.pumpWidget(
      MaterialApp(
        home: HomeworkFormScreen(
          speech: SpeechCoordinator(audio),
          studentId: 2,
          repository: repo,
          onBack: () {},
          onSaved: () => saved = true,
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNWidgets(4));
    await tester.enterText(
      find.widgetWithText(TextField, 'Gyakorlandó szöveg').first,
      'alma, körte',
    );
    await tester.tap(find.text('Új sor'));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(TextField, 'Gyakorlandó szöveg'),
      findsNWidgets(2),
    );
    await tester.ensureVisible(find.text('Feladás'));
    await tester.tap(find.text('Feladás'));
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    expect(repo.created!.single.text, 'alma, körte');
    expect(repo.created!.single.repetitions, 1);
    expect(
      repo.deadline!.difference(DateTime.now()).inHours,
      greaterThanOrEqualTo(23),
    );
  });
  testWidgets('completion queues the homework and announces server result', (
    tester,
  ) async {
    final audio = FakeAudioService();
    final repo = FakeHomeworkRepository();
    final events = ValueNotifier<HomeworkSyncEvent?>(null);
    final id = 'b' * 32;
    final data = HomeworkData(
      id: id,
      trainerName: 'Tanár',
      deadline: DateTime.now().add(const Duration(hours: 1)),
      expired: false,
      submitted: false,
      entries: const [HomeworkEntryData('a', 1)],
      exercise: {
        'id': 'homework_$id',
        'title': 'Házi feladat',
        'type': 'homework',
        'baselineSeconds': 7.5,
        'units': [
          {
            'id': 'unit',
            'text': 'a',
            'sentenceAudio': 'assets/audio/menu_logout.wav',
            'wordAudio': ['assets/audio/menu_logout.wav'],
          },
        ],
      },
    );
    repo.loaded = data;
    final snapshots = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        home: HomeworkPracticeScreen(
          homework: data,
          speech: SpeechCoordinator(audio),
          records: PracticeRecords(),
          repository: repo,
          events: events,
          onAttempt: (snapshot) {
            snapshots.add(snapshot);
            if (snapshot['status'] == 'completed') {
              events.value = HomeworkSyncEvent(
                snapshot['id'] as String,
                'pending',
              );
            }
          },
          onBack: () {},
          onMain: () {},
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA, character: 'a');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    expect(snapshots.last['status'], 'completed');
    expect(snapshots.last['activity_type'], 'homework');
    expect(find.text('Újrapróbálás'), findsOneWidget);
    events.value = HomeworkSyncEvent(snapshots.last['id'] as String, 'saved');
    await tester.pumpAndSettle();
    expect(find.text('Beadva'), findsOneWidget);
    expect(
      audio.spoken,
      contains('assets/audio/homework_completion_saved.wav'),
    );
    await tester.pumpWidget(const SizedBox());
    events.dispose();
  });

  testWidgets('trainer hears latest attempt and can reopen by keyboard', (
    tester,
  ) async {
    final audio = FakeAudioService();
    var reopened = false;
    var history = false;
    final attempt = HomeworkAttemptData(
      id: 'attempt',
      submittedAt: DateTime(2026, 1, 1, 12, 30),
      durationMs: 33000,
      mistakes: 2,
      score: 135,
      keys: const [KeyProgress(key: 'a', correct: 3, incorrect: 1)],
    );
    final item = HomeworkData(
      id: 'a' * 32,
      trainerName: 'Tanár',
      deadline: DateTime.now().subtract(const Duration(hours: 1)),
      expired: true,
      submitted: true,
      entries: const [HomeworkEntryData('alma', 1)],
      attempts: [attempt],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeworkListScreen(
          studentId: 2,
          speech: SpeechCoordinator(audio),
          loadHomeworks: () async => [item],
          onBack: () {},
          onClose: () {},
          onOpen: (_) {},
          onHistory: (_) => history = true,
          onReopen: (_) => reopened = true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      audio.spoken,
      contains('assets/audio/homework_trainer_list_help.wav'),
    );
    expect(audio.spoken, contains('assets/audio/progress_correct.wav'));
    expect(audio.spoken, contains('assets/audio/progress_incorrect.wav'));
    expect(find.textContaining('Pontszám: 135'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    expect(reopened, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(history, isTrue);
  });

  testWidgets('expired student homework is spoken and cannot be opened', (
    tester,
  ) async {
    final audio = FakeAudioService();
    var opened = false;
    final item = HomeworkData(
      id: 'a' * 32,
      trainerName: 'Tanár',
      deadline: DateTime.now().subtract(const Duration(hours: 1)),
      expired: true,
      submitted: false,
      entries: const [HomeworkEntryData('alma', 1)],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeworkListScreen(
          speech: SpeechCoordinator(audio),
          loadHomeworks: () async => [item],
          onBack: () {},
          onClose: () {},
          onOpen: (_) => opened = true,
          onHistory: (_) {},
          onReopen: (_) {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      audio.spoken,
      contains('assets/audio/homework_status_expired_unsubmitted.wav'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(opened, isFalse);
    expect(audio.spoken.last, 'assets/audio/homework_start_expired.wav');
  });
}
