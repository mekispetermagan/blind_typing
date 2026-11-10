import 'dart:io';
import 'dart:ui' as ui;

import 'package:blind_typing/controllers/typing_controller.dart';

import 'support/content_fixtures.dart';

import 'package:blind_typing/widgets/current_word.dart';
import 'package:blind_typing/widgets/sentence_display.dart';
import 'package:blind_typing/screens/typing_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    final loader = FontLoader('DejaVuSansMono')
      ..addFont(rootBundle.load('assets/fonts/DejaVuSansMono.ttf'));
    await loader.load();
    final icons = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await icons.load();
  });
  testWidgets('reveals letters without shifting any character slot', (
    tester,
  ) async {
    Future<void> render(int count) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: CurrentWord(word: 'Almát', acceptedLetters: count),
          ),
        ),
      ),
    );
    await render(0);
    final firstPosition = tester.getTopLeft(
      find.byKey(const ValueKey('letter-slot-0')),
    );
    final lastPosition = tester.getTopLeft(
      find.byKey(const ValueKey('letter-slot-4')),
    );
    await render(4);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('letter-slot-0'))),
      firstPosition,
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('letter-slot-4'))),
      lastPosition,
    );
    expect(find.text('A'), findsOneWidget);
    expect(find.text('á'), findsOneWidget);
    expect(find.text('t'), findsNothing);
  });

  testWidgets('completed sentence words are green and future words grey', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SentenceDisplay(words: ['Anna', 'almát'], completedWords: 1),
      ),
    );
    final text = tester.widget<Text>(find.byType(Text));
    final spans = (text.textSpan! as TextSpan).children!.cast<TextSpan>();
    expect(spans.first.style!.color, Colors.greenAccent.shade200);
    expect(spans.last.style!.color, Colors.grey.shade400);
  });

  testWidgets(
    'Advanced shows the actual error suffix, including overflow, and deletion hides future letters',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        Future<void> render(List<String> entered) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: CurrentWord(
                word: 'Anna',
                acceptedLetters: 1,
                enteredCharacters: entered,
              ),
            ),
          ),
        );
        await render(['A', 'x', 'n', 'n', 'a']);
        final context = tester.element(find.byType(CurrentWord));
        final errorColor = Theme.of(context).colorScheme.error;
        expect(find.bySemanticsLabel('Axnna'), findsOneWidget);
        for (var index = 1; index < 5; index++) {
          final letter = tester.widget<Text>(
            find.byKey(ValueKey('letter-$index')),
          );
          expect(letter.style!.color, errorColor);
        }
        final cursor = tester.widget<Container>(
          find.byKey(const ValueKey('letter-slot-5')),
        );
        expect((cursor.decoration! as BoxDecoration).border, isNotNull);
        await render(['A']);
        expect(find.bySemanticsLabel('A'), findsOneWidget);
        expect(find.text('x'), findsNothing);
        expect(find.text('n'), findsNothing);
        expect(find.byKey(const ValueKey('letter-slot-4')), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('desktop screen routes controls and character events', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var starts = 0;
    var repeats = 0;
    var spells = 0;
    var keyDowns = 0;
    var modeToggles = 0;
    var backspaces = 0;
    final spellingEvents = <String>[];
    var pauses = 0;
    var closes = 0;
    final characters = <String>[];
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.teal,
            brightness: Brightness.dark,
          ),
          fontFamily: 'DejaVuSansMono',
        ),
        home: RepaintBoundary(
          key: boundaryKey,
          child: TypingScreen(
            sentence: sampleSentences.first,
            sentenceIndex: 0,
            sentenceCount: 5,
            wordIndex: 1,
            letterIndex: 3,
            enteredCharacters: const ['a', 'l', 'm', 'x', 'x', 'x'],
            mode: TypingMode.advanced,
            phase: ExercisePhase.typing,
            countdown: null,
            onStart: () => starts++,
            onRepeat: () => repeats++,
            onSpell: () {
              spells++;
              spellingEvents.add('spell');
            },
            onKeyDown: () {
              keyDowns++;
              spellingEvents.add('cancel');
            },
            onToggleMode: () => modeToggles++,
            onBackspace: () => backspaces++,
            onPause: () => pauses++,
            onClose: () => closes++,
            onCharacter: characters.add,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f2);
    expect(spellingEvents, ['cancel', 'spell']);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f2);
    expect(spellingEvents, ['cancel', 'spell']);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f2);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f2);
    expect(spells, 2);
    expect(spellingEvents.last, 'cancel');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f2);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA, character: 'A');
    await tester.sendKeyEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.f3);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.f3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.f3);
    await tester.sendKeyEvent(LogicalKeyboardKey.f4);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(starts, 1);
    expect(repeats, 1);
    expect(spells, 2);
    expect(keyDowns, 14);
    expect(modeToggles, 1);
    expect(backspaces, 1);
    expect(find.text('Haladó mód'), findsOneWidget);
    expect(pauses, 1);
    expect(closes, 2);
    expect(characters, ['A']);
    expect(tester.takeException(), isNull);

    const screenshotPath = String.fromEnvironment('SCREENSHOT_PATH');
    if (screenshotPath.isNotEmpty) {
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(screenshotPath).writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }
  });
}
