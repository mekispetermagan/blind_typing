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
    'spoken menus, F teaching, 24 drills, and sample practice work with native audio',
    (tester) async {
      app.main();
      final repository = AssetContentRepository();
      final catalog = await repository.loadMenu();
      Future<TypingExercise> exercise(ActivityType type) async =>
          await repository.loadExercise(
            catalog.root.descendants
                .firstWhere((node) => node.activity?.type == type)
                .activity!,
          ) as TypingExercise;
      final drills = await exercise(ActivityType.words);
      final practice = await exercise(ActivityType.practice);
      TypingScreen typing() =>
          tester.widget<TypingScreen>(find.byType(TypingScreen));
      MenuScreen menu() => tester.widget<MenuScreen>(find.byType(MenuScreen));
      Future<void> waitFor(bool Function() condition) async {
        final clock = Stopwatch()..start();
        while (!condition()) {
          await tester.pump(const Duration(milliseconds: 100));
          if (clock.elapsed > const Duration(seconds: 40)) {
            fail(
              'Timed out: menu=${find.byType(MenuScreen).evaluate().isNotEmpty}, '
              'typing=${find.byType(TypingScreen).evaluate().isEmpty ? null : typing().phase}',
            );
          }
        }
      }

      Future<void> key(LogicalKeyboardKey key, {String? character}) async {
        await tester.sendKeyEvent(key, character: character);
        await tester.pump();
      }

      Future<void> waitTyping(ExercisePhase phase) => waitFor(
        () =>
            find.byType(TypingScreen).evaluate().isNotEmpty &&
            typing().phase == phase,
      );
      Future<void> waitMenu() =>
          waitFor(() => find.byType(MenuScreen).evaluate().isNotEmpty);

      await waitMenu();
      await key(LogicalKeyboardKey.enter); // LECKÉK
      await key(LogicalKeyboardKey.enter); // ASDFJKLÉ
      await key(LogicalKeyboardKey.enter); // betűk
      await waitFor(() => find.byType(TeachingScreen).evaluate().isNotEmpty);
      await key(LogicalKeyboardKey.enter);
      for (final character in ['g', 'f', 'g', 'F', 'f']) {
        await key(LogicalKeyboardKey.keyF, character: character);
      }
      await waitMenu();
      expect(menu().title, 'Kész a feladat');
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.enter); // Back to lesson menu
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.enter); // gyakorlatok
      await waitTyping(ExercisePhase.ready);
      await key(LogicalKeyboardKey.f3);
      expect(typing().mode, TypingMode.advanced);
      await key(LogicalKeyboardKey.enter);
      await key(LogicalKeyboardKey.keyX, character: 'x');
      await key(LogicalKeyboardKey.keyN, character: 'n');
      expect(typing().enteredCharacters, ['x', 'n']);
      await key(LogicalKeyboardKey.f2);
      await tester.pump(const Duration(milliseconds: 100));
      await key(LogicalKeyboardKey.backspace);
      await key(LogicalKeyboardKey.backspace);
      await key(LogicalKeyboardKey.keyA, character: 'a');
      await key(LogicalKeyboardKey.escape);
      await waitMenu();
      expect(menu().title, 'Szünet');
      await key(LogicalKeyboardKey.enter);
      expect(typing().enteredCharacters, ['a']);
      await key(LogicalKeyboardKey.backspace);
      expect(typing().enteredCharacters, isEmpty);
      for (final unit in drills.units) {
        for (final character in unit.text.split('')) {
          await key(LogicalKeyboardKey.keyA, character: character);
        }
      }
      await waitMenu();
      expect(menu().title, 'Kész a feladat');
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.enter);
      await key(LogicalKeyboardKey.arrowLeft);
      await key(LogicalKeyboardKey.arrowLeft);
      await key(LogicalKeyboardKey.arrowDown); // GYAKORLÁS
      await key(LogicalKeyboardKey.enter);
      await key(LogicalKeyboardKey.enter); // könnyű
      await key(LogicalKeyboardKey.enter); // sample
      await waitTyping(ExercisePhase.ready);
      expect(typing().mode, TypingMode.advanced);
      await key(LogicalKeyboardKey.enter);
      for (var index = 0; index < practice.units.length; index++) {
        await waitTyping(ExercisePhase.typing);
        expect(typing().sentenceIndex, index);
        for (final character in practice.units[index].text.split('')) {
          await key(LogicalKeyboardKey.keyA, character: character);
        }
      }
      await waitMenu();
      expect(menu().title, 'Kész a feladat');
      await key(LogicalKeyboardKey.enter); // Restart retains mode
      await waitTyping(ExercisePhase.reading);
      expect(typing().mode, TypingMode.advanced);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 300));
    },
  );
}
