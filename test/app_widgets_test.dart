import 'dart:io';
import 'dart:ui' as ui;

import 'package:blind_typing/app.dart';
import 'package:blind_typing/controllers/app_controller.dart';
import 'package:blind_typing/models/menu.dart';
import 'package:blind_typing/models/typing_state.dart';
import 'package:blind_typing/screens/menu_screen.dart';
import 'package:blind_typing/screens/teaching_screen.dart';
import 'package:blind_typing/screens/typing_screen.dart';
import 'package:blind_typing/services/speech_coordinator.dart';
import 'package:blind_typing/widgets/menu_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/content_fixtures.dart';
import 'support/fake_audio_service.dart';

void main() {
  setUpAll(() async {
    await (FontLoader(
      'DejaVuSansMono',
    )..addFont(rootBundle.load('assets/fonts/DejaVuSansMono.ttf'))).load();
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  testWidgets(
    'keyboard menus launch both lesson activities, preserve correction state, and return to practice',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final audio = FakeAudioService();
      final app = AppController(
        content: FileContentRepository(),
        speech: SpeechCoordinator(audio),
        countdownInterval: Duration.zero,
      );
      final boundary = GlobalKey();
      var closes = 0;
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: TypingApp(controller: app, onClose: () => closes++),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> key(LogicalKeyboardKey key, {String? character}) async {
        await tester.sendKeyEvent(key, character: character);
        await tester.pump();
      }

      Future<void> capture(String name) async {
        const directory = String.fromEnvironment('APP_SCREENSHOT_DIR');
        if (directory.isEmpty) return;
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$directory/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      expect(find.byType(MenuScreen), findsOneWidget);
      await capture('main_menu');
      await key(LogicalKeyboardKey.enter);
      await key(LogicalKeyboardKey.arrowRight);
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(TeachingScreen), findsOneWidget);
      await capture('teaching');
      await key(LogicalKeyboardKey.enter);
      for (final character in ['g', 'f', 'g', 'F', 'f']) {
        await key(LogicalKeyboardKey.keyF, character: character);
      }
      expect(app.menu.id, 'complete_menu');
      expect(find.textContaining('A hibás leütések száma 2.'), findsOneWidget);
      expect(find.text('Következő gyakorlat'), findsOneWidget);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.enter);
      expect(find.byType(TypingScreen), findsOneWidget);
      await key(LogicalKeyboardKey.enter);
      await key(LogicalKeyboardKey.f3);
      await key(LogicalKeyboardKey.keyA, character: 'a');
      await key(LogicalKeyboardKey.keyX, character: 'x');
      expect(app.typing!.enteredText, 'ax');
      await capture('word_drill');
      await key(LogicalKeyboardKey.escape);
      expect(app.menu.id, 'pause_menu');
      await capture('pause_menu');
      await key(LogicalKeyboardKey.enter);
      expect(app.typing!.enteredText, 'ax');
      await key(LogicalKeyboardKey.backspace);
      expect(app.typing!.enteredText, 'a');
      await key(LogicalKeyboardKey.escape);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.enter);
      await key(LogicalKeyboardKey.arrowLeft);
      await key(LogicalKeyboardKey.arrowLeft);
      await key(LogicalKeyboardKey.arrowDown);
      await key(LogicalKeyboardKey.enter);
      await key(LogicalKeyboardKey.enter);
      await key(LogicalKeyboardKey.enter);
      expect(app.typing!.exercise.id, 'sample_practice');
      expect(app.typing!.mode, TypingMode.advanced);
      await key(LogicalKeyboardKey.f4);
      expect(closes, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      expect(audio.disposed, isTrue);
    },
  );

  testWidgets('long data-driven menus keep keyboard selection visible', (
    tester,
  ) async {
    final items = List.generate(
      30,
      (index) => MenuNode(
        id: 'item_$index',
        title: 'Item $index',
        command: MenuCommand.menu,
      ),
    );
    Future<void> render(int selected) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MenuList(
            items: items,
            selectedIndex: selected,
            onActivate: (_) {},
          ),
        ),
      ),
    );
    await render(0);
    await render(29);
    await tester.pump();
    final item = find.text('Item 29');
    expect(item, findsOneWidget);
    expect(
      tester.getRect(item).bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height),
    );
    await render(0);
    await tester.pump();
    expect(find.text('Item 0'), findsOneWidget);
  });
}
