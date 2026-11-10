import 'package:blind_typing/controllers/typing_controller.dart';
import 'package:blind_typing/main.dart' as app;
import 'package:blind_typing/models/sentence.dart';
import 'package:blind_typing/widgets/typing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Linux audio and keyboard flow completes all five sentences', (
    tester,
  ) async {
    app.main();

    TypingScreen screen() =>
        tester.widget<TypingScreen>(find.byType(TypingScreen));

    Future<void> waitFor(ExercisePhase phase) async {
      final clock = Stopwatch()..start();
      while (find.byType(TypingScreen).evaluate().isEmpty ||
          screen().phase != phase) {
        await tester.pump(const Duration(milliseconds: 100));
        if (find.byType(TypingScreen).evaluate().isNotEmpty) {
          expect(
            screen().phase,
            isNot(ExercisePhase.error),
            reason: 'Native audio initialization/playback failed',
          );
        }
        if (clock.elapsed > const Duration(seconds: 30)) {
          fail('Timed out waiting for $phase');
        }
      }
    }

    await waitFor(ExercisePhase.ready);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);

    for (var index = 0; index < sampleSentences.length; index++) {
      await waitFor(ExercisePhase.typing);
      expect(screen().sentenceIndex, index);
      if (index == 0) {
        await tester.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
        await tester.pump();
        expect(screen().letterIndex, 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.f1);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(screen().phase, ExercisePhase.paused);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pump();
        expect(screen().phase, ExercisePhase.typing);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'a');
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pump(const Duration(milliseconds: 100));
        expect(screen().letterIndex, 1);
        expect(screen().phase, ExercisePhase.typing);
        await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(screen().letterIndex, 1);
      }
      // Deliberately type much faster than the spoken words finish. Character
      // strings include accents; physical key identity is not used for matching.
      final text = sampleSentences[index].text.toLowerCase();
      for (final character in (index == 0 ? text.substring(1) : text).split(
        '',
      )) {
        await tester.sendKeyEvent(
          LogicalKeyboardKey.keyA,
          character: character,
        );
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    await waitFor(ExercisePhase.complete);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(screen().sentenceIndex, 0);
    expect(screen().phase, ExercisePhase.reading);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 300));
  });
}
