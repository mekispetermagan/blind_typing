import 'package:blind_typing/api/trainer_repository.dart';
import 'package:blind_typing/screens/student_selection_screen.dart';
import 'package:blind_typing/services/speech_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_audio_service.dart';

void main() {
  testWidgets(
    'speaks names, supports keyboard selection and restores selection',
    (tester) async {
      final audio = FakeAudioService();
      TrainerStudent? chosen;
      const first = TrainerStudent(
        id: 1,
        name: 'Péter',
        nameAudioRevision: '0123456789abcdef',
      );
      const second = TrainerStudent(id: 2, name: 'Éva');
      await tester.pumpWidget(
        MaterialApp(
          home: StudentSelectionScreen(
            speech: SpeechCoordinator(audio),
            loadStudents: () async => [first, second],
            initialStudentId: 2,
            onSelect: (value) => chosen = value,
            onBack: () {},
            onClose: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(audio.spoken, contains('assets/audio/letter_00e9.wav'));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(
        audio.spoken.last,
        'assets/audio/student_name_1_0123456789abcdef.wav',
      );
      audio.spoken.clear();
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await tester.pumpAndSettle();
      expect(
        audio.spoken.last,
        'assets/audio/student_name_1_0123456789abcdef.wav',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(chosen, first);
    },
  );

  testWidgets('empty list speaks its state and permits returning', (
    tester,
  ) async {
    final audio = FakeAudioService();
    var returned = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StudentSelectionScreen(
          speech: SpeechCoordinator(audio),
          loadStudents: () async => [],
          onSelect: (_) {},
          onBack: () => returned = true,
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(audio.spoken, contains('assets/audio/student_selection_empty.wav'));
    expect(find.text('Nincsenek hozzád rendelt tanulók.'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(returned, isTrue);
  });

  testWidgets('failure is spoken and Enter retries', (tester) async {
    final audio = FakeAudioService();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: StudentSelectionScreen(
          speech: SpeechCoordinator(audio),
          loadStudents: () async {
            if (calls++ == 0) throw StateError('offline');
            return [];
          },
          onSelect: (_) {},
          onBack: () {},
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      audio.spoken,
      contains('assets/audio/student_selection_failure.wav'),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(audio.spoken, contains('assets/audio/student_selection_empty.wav'));
  });
}
