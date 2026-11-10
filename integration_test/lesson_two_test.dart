import 'package:blind_typing/main.dart' as app;
import 'package:blind_typing/models/exercise.dart';
import 'package:blind_typing/models/typing_state.dart';
import 'package:blind_typing/screens/menu_screen.dart';
import 'package:blind_typing/screens/teaching_screen.dart';
import 'package:blind_typing/screens/typing_screen.dart';
import 'package:blind_typing/services/content_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'lesson 2 teaches F→R/K→I and completes all three word sessions with native audio',
    (tester) async {
      app.main();
      final repository = AssetContentRepository();
      final catalog = await repository.loadMenu();
      final lesson = catalog.root.descendants.firstWhere(
        (node) => node.id == 'upper_row_ir',
      );
      final exercises = <TypingExercise>[];
      for (final node in lesson.children.skip(1)) {
        exercises.add(
          await repository.loadExercise(node.activity!) as TypingExercise,
        );
      }
      MenuScreen menu() => tester.widget<MenuScreen>(find.byType(MenuScreen));
      TeachingScreen teaching() =>
          tester.widget<TeachingScreen>(find.byType(TeachingScreen));
      TypingScreen typing() =>
          tester.widget<TypingScreen>(find.byType(TypingScreen));
      Future<void> waitFor(bool Function() condition) async {
        final clock = Stopwatch()..start();
        while (!condition()) {
          await tester.pump(const Duration(milliseconds: 100));
          if (clock.elapsed > const Duration(seconds: 40)) {
            fail(
              'Timed out: menu=${find.byType(MenuScreen).evaluate().isEmpty ? null : menu().title}, '
              'teaching=${find.byType(TeachingScreen).evaluate().isEmpty ? null : teaching().state.phase}, '
              'typing=${find.byType(TypingScreen).evaluate().isEmpty ? null : typing().phase}',
            );
          }
        }
      }

      Future<void> key(LogicalKeyboardKey key, {String? character}) async {
        await tester.sendKeyEvent(key, character: character);
        await tester.pump();
      }

      Future<void> waitMenu() =>
          waitFor(() => find.byType(MenuScreen).evaluate().isNotEmpty);
      Future<void> waitStep(String target) => waitFor(
        () =>
            find.byType(TeachingScreen).evaluate().isNotEmpty &&
            teaching().state.phase == ExercisePhase.typing &&
            teaching().step.key == target,
      );

      await waitMenu();
      await key(LogicalKeyboardKey.enter); // LECKÉK
      await key(LogicalKeyboardKey.arrowDown); // I, R
      await key(LogicalKeyboardKey.enter);
      expect(menu().title, 'I, R');
      await key(LogicalKeyboardKey.enter);
      await waitFor(() => find.byType(TeachingScreen).evaluate().isNotEmpty);
      await key(LogicalKeyboardKey.enter);
      await key(LogicalKeyboardKey.keyD, character: 'd');
      expect(teaching().state.successes, 0);
      await key(LogicalKeyboardKey.keyF, character: 'f');
      await waitStep('R');
      await key(LogicalKeyboardKey.keyR, character: 'r');
      await key(LogicalKeyboardKey.keyF, character: 'f');
      expect(teaching().state.successes, 1);
      await key(LogicalKeyboardKey.keyR, character: 'r');
      await key(LogicalKeyboardKey.keyR, character: 'R');
      await waitStep('K');
      await key(LogicalKeyboardKey.keyK, character: 'k');
      await waitStep('I');
      await key(LogicalKeyboardKey.keyI, character: 'i');
      await key(LogicalKeyboardKey.keyK, character: 'k');
      expect(teaching().state.successes, 1);
      await key(LogicalKeyboardKey.keyI, character: 'I');
      await key(LogicalKeyboardKey.keyI, character: 'i');
      await waitMenu();
      expect(menu().title, 'Kész a feladat');
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.enter);
      await key(LogicalKeyboardKey.f3);

      for (var session = 0; session < exercises.length; session++) {
        await key(LogicalKeyboardKey.arrowDown);
        await key(LogicalKeyboardKey.enter);
        await waitFor(
          () =>
              find.byType(TypingScreen).evaluate().isNotEmpty &&
              typing().phase == ExercisePhase.ready,
        );
        expect(typing().mode, TypingMode.advanced);
        expect(typing().sentenceCount, exercises[session].units.length);
        await key(LogicalKeyboardKey.enter);
        for (final unit in exercises[session].units) {
          for (final character in unit.text.toLowerCase().split('')) {
            await key(LogicalKeyboardKey.keyA, character: character);
          }
        }
        await waitMenu();
        expect(menu().title, 'Kész a feladat');
        await key(LogicalKeyboardKey.arrowDown);
        await key(LogicalKeyboardKey.enter);
        expect(menu().title, 'I, R');
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
}
