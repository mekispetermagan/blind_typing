import 'dart:io';

import 'package:blind_typing/api/audio_cache.dart';
import 'package:blind_typing/api/http_content_repository.dart';
import 'package:blind_typing/app.dart';
import 'package:blind_typing/controllers/app_controller.dart';
import 'package:blind_typing/screens/progress_screen.dart';
import 'package:blind_typing/services/soloud_audio_service.dart';
import 'package:blind_typing/services/speech_coordinator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('progress speech loads and navigates with native audio', (
    tester,
  ) async {
    final cache = await Directory.systemTemp.createTemp(
      'typing-progress-audio',
    );
    addTearDown(() => cache.delete(recursive: true));
    final controller = AppController(
      content: HttpContentRepository(),
      speech: SpeechCoordinator(
        SoloudAudioService(cache: AudioCache(root: cache)),
      ),
    );
    await tester.pumpWidget(TypingApp(controller: controller, onClose: () {}));
    Future<void> waitFor(bool Function() condition) async {
      final stopwatch = Stopwatch()..start();
      while (!condition()) {
        await tester.pump(const Duration(milliseconds: 100));
        if (stopwatch.elapsed > const Duration(seconds: 90)) {
          fail(
            'Timed out waiting for progress speech; page: ${controller.page}',
          );
        }
      }
    }

    await waitFor(() => controller.page == AppPage.menu);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await waitFor(() => find.text('Betűstatisztika').evaluate().isNotEmpty);
    expect(find.byType(ProgressScreen), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(controller.page, AppPage.menu);
    expect(controller.selectedIndex, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
