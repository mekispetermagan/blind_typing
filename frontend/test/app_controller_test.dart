import 'package:blind_typing/controllers/app_controller.dart';
import 'package:blind_typing/models/exercise.dart';
import 'package:blind_typing/models/menu.dart';
import 'package:blind_typing/models/typing_state.dart';
import 'package:blind_typing/services/audio_service.dart';
import 'package:blind_typing/services/speech_coordinator.dart';
import 'package:blind_typing/services/practice_records.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/content_fixtures.dart';
import 'support/fake_audio_service.dart';

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeAudioService audio;
  late FileContentRepository content;
  late AppController app;
  setUp(() {
    audio = FakeAudioService();
    content = FileContentRepository();
    app = AppController(
      content: content,
      speech: SpeechCoordinator(audio),
      countdownInterval: Duration.zero,
    );
  });
  tearDown(() => app.dispose());

  test('menu depth, labels, and activity dispatch come from data', () async {
    final original = await content.loadMenu();
    var node = MenuNode(
      id: 'new_activity',
      title: 'New title',
      activity: original.root.descendants
          .firstWhere((node) => node.activity?.type == ActivityType.words)
          .activity,
    );
    for (var index = 0; index < 5; index++) {
      node = MenuNode(
        id: 'new_branch_$index',
        title: 'Level $index',
        children: [node],
      );
    }
    content.menuOverride = MenuCatalog(
      root: node,
      pause: original.pause,
      complete: original.complete,
    );
    await app.initialize();
    for (var index = 0; index < 5; index++) {
      app.activate();
    }
    await settle();
    expect(app.page, AppPage.typing);
    expect(app.typing!.exercise.id, 'home_row_words');
  });

  Future<void> lessonMenu() async {
    await app.initialize();
    app.activate(); // LECKÉK
    app.activate(); // ASDFJKLÉ
    await settle();
  }

  void finishWordDrill() {
    final typing = app.typing!;
    typing.start();
    for (final unit in typing.exercise.units) {
      for (final character in unit.text.split('')) {
        typing.typeCharacter(character);
      }
    }
    expect(app.activityPhase, ExercisePhase.complete);
  }

  test('navigation speaks selection, cancels previous speech, and retains parent selection', () async {
    await app.initialize();
    expect(content.loaded, isEmpty); // Exercise recordings load on entry.
    audio.holdSpeech = true;
    app.repeat();
    app.moveSelection(1);
    await settle();
    expect(app.selectedIndex, 1);
    expect(audio.interrupted, isNotEmpty);
    expect(audio.spoken.last, 'assets/audio/menu_challenges.wav');
    app.activate();
    app.back();
    expect(app.menu.id, 'main');
    expect(app.selectedIndex, 1);
  });

  test(
    'completion menu advances within and across lessons using shared audio',
    () async {
      await lessonMenu();
      app.activate();
      await settle();
      expect(app.page, AppPage.teaching);
      app.teaching!.start();
      for (final key in ['f', 'g', 'F', 'f']) {
        app.teaching!.typeCharacter(key);
      }
      expect(app.page, AppPage.menu);
      expect(app.menu.id, 'complete_menu');
      expect(app.menu.children.map((entry) => entry.command), [
        MenuCommand.restart,
        MenuCommand.nextExercise,
        MenuCommand.menu,
      ]);
      app.moveSelection(1);
      expect(audio.spoken.last, 'assets/audio/menu_complete_next_exercise.wav');
      app.activate();
      await settle();
      expect(app.page, AppPage.typing);
      expect(app.teaching, isNull);
      expect(app.typing!.exercise.id, 'home_row_words');
      app.toggleMode();
      finishWordDrill();
      expect(app.menu.children.map((entry) => entry.command), [
        MenuCommand.restart,
        MenuCommand.nextLesson,
        MenuCommand.menu,
      ]);
      app.moveSelection(1);
      expect(audio.spoken.last, 'assets/audio/menu_complete_next_lesson.wav');
      app.activate();
      await settle();
      expect(app.page, AppPage.teaching);
      expect(app.typing, isNull);
      expect(app.teaching!.exercise.id, 'upper_row_ir_letters');
      expect(app.mode, TypingMode.advanced);
      expect(audio.disposed, isFalse);
      app.returnToMenu();
      expect(app.menu.id, 'upper_row_ir');
      expect(app.selectedIndex, 0);
    },
  );

  test('the final lesson activity offers restart and return', () async {
    await app.initialize();
    app.activate(); // LECKÉK
    app.activateIndex(app.menu.children.length - 1);
    final lessonId = app.menu.id;
    final lastIndex = app.menu.children.length - 1;
    app.activateIndex(lastIndex);
    await settle();
    finishWordDrill();
    expect(app.menu.children.map((entry) => entry.command), [
      MenuCommand.restart,
      MenuCommand.menu,
    ]);
    app.moveSelection(1);
    app.activate();
    expect(app.menu.id, lessonId);
    expect(app.selectedIndex, lastIndex);
  });

  test(
    'mode and input survive pause, restart, and navigating to another activity',
    () async {
      await lessonMenu();
      app.toggleMode();
      app.moveSelection(1);
      app.activate();
      await settle();
      app.typing!.start();
      app.typing!.typeCharacter('a');
      app.typing!.typeCharacter('x');
      app.pauseActivity();
      expect(app.menu.id, 'pause_menu');
      app.activate(); // Resume
      expect(app.typing!.enteredText, 'ax');
      app.pauseActivity();
      app.moveSelection(1);
      app.activate(); // Restart
      expect(app.typing!.enteredText, isEmpty);
      expect(app.mode, TypingMode.advanced);
      app.returnToMenu();
      app.back();
      app.back();
      app.moveSelection(1);
      app.activate();
      app.activate();
      await settle();
      expect(app.typing!.exercise.id, 'challenge_easy');
      expect(app.typing!.mode, TypingMode.advanced);
    },
  );

  test('content errors are recoverable and never leave an unusable activity selected', () async {
    await lessonMenu();
    content.failExercise = true;
    app.activate();
    await settle();
    expect(app.page, AppPage.error);
    expect(audio.spoken.last, AudioCues.contentError);
    app.back();
    expect(app.page, AppPage.menu);
    content.failExercise = false;
    app.activate();
    await settle();
    expect(app.page, AppPage.teaching);
  });

  test('an activity is usable while its welcome is still playing', () async {
    await lessonMenu();
    audio.holdSpeech = true;
    app.activate();
    await settle();
    expect(app.page, AppPage.teaching);
    expect(app.teaching!.state.phase, ExercisePhase.ready);
    app.teaching!.start();
    app.teaching!.typeCharacter('f');
    expect(app.teaching!.state.successes, 1);
  });
  test('retry reloads the failed activity at the same menu location', () async {
    await lessonMenu();
    content.failExercise = true;
    app.activate();
    await settle();
    content.failExercise = false;
    await app.retry();
    expect(app.page, AppPage.teaching);
    expect(app.menu.id, 'home_row');
  });

  test(
    'record loading failure offers retry without starting an activity',
    () async {
      var calls = 0;
      final retryApp = AppController(
        content: content,
        speech: SpeechCoordinator(audio),
        records: PracticeRecords(
          read: () async {
            if (++calls == 1) throw StateError('temporary failure');
            return null;
          },
        ),
      );
      addTearDown(retryApp.dispose);
      await retryApp.initialize();
      expect(retryApp.page, AppPage.error);
      await retryApp.retry();
      expect(calls, 2);
      expect(retryApp.page, AppPage.menu);
    },
  );

  test(
    'activity-specific assets are released when returning to menu',
    () async {
      await lessonMenu();
      app.activate();
      await settle();
      expect(audio.activityAssets, isNotEmpty);
      app.returnToMenu();
      await settle();
      expect(audio.activityAssets, isEmpty);
    },
  );
}
