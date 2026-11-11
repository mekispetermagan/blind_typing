import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/exercise.dart';
import '../models/menu.dart';
import '../services/audio_service.dart';
import '../services/content_repository.dart';
import '../services/speech_coordinator.dart';
import 'letter_teaching_controller.dart';
import 'typing_controller.dart';

enum AppPage { loading, menu, typing, teaching, error }

/// Owns navigation and shared services; exercise rules belong to managers.
class AppController extends ChangeNotifier {
  AppController({
    required this._content,
    required this._speech,
    this.countdownInterval = const Duration(seconds: 1),
  });

  final ContentRepository _content;
  final SpeechCoordinator _speech;
  final Duration countdownInterval;
  MenuCatalog? _catalog;
  final List<MenuNode> _path = [];
  final List<int> _selections = [];
  int _sessionSelection = 0;
  TypingMode _mode = TypingMode.simple;
  TypingController? _typing;
  LetterTeachingController? _teaching;
  ExercisePhase? _lastPhase;
  bool _loading = true;
  bool _disposed = false;
  String? _failure;
  int _generation = 0;

  TypingController? get typing => _typing;
  LetterTeachingController? get teaching => _teaching;
  TypingMode get mode => _mode;
  ExercisePhase? get activityPhase => _typing?.phase ?? _teaching?.state.phase;
  MenuNode? get _activityMenu => switch (activityPhase) {
    ExercisePhase.paused => _catalog?.pause,
    ExercisePhase.complete => _catalog?.complete,
    _ => null,
  };
  AppPage get page {
    if (_loading) return AppPage.loading;
    if (_failure != null || activityPhase == ExercisePhase.error) {
      return AppPage.error;
    }
    if (_activityMenu != null || (_typing == null && _teaching == null)) {
      return AppPage.menu;
    }
    return _typing != null ? AppPage.typing : AppPage.teaching;
  }

  MenuNode get menu {
    final activityMenu = _activityMenu;
    if (activityMenu == null) return _path.last;
    if (activityPhase != ExercisePhase.complete) return activityMenu;

    final next = _nextLessonActivity;
    final command = next == null
        ? null
        : next[1] == _selections[1]
        ? MenuCommand.nextExercise
        : MenuCommand.nextLesson;
    return MenuNode(
      id: activityMenu.id,
      title: activityMenu.title,
      children: [
        for (final child in activityMenu.children)
          if (child.command?.isProgression != true || child.command == command)
            child,
      ],
    );
  }

  List<int>? get _nextLessonActivity {
    if (_path.length < 3 || _path[1].id != 'lessons') return null;

    // Find the next sibling within LECKÉK, then descend to its first activity.
    for (var depth = _path.length - 1; depth >= 1; depth--) {
      final siblings = _path[depth].children;
      final next = _selections[depth] + 1;
      if (next >= siblings.length) continue;

      final route = [..._selections.take(depth), next];
      var node = siblings[next];
      while (node.children.isNotEmpty) {
        route.add(0);
        node = node.children.first;
      }
      return route;
    }
    return null;
  }

  int get selectedIndex =>
      _activityMenu != null ? _sessionSelection : _selections.last;
  String get breadcrumb => _path.map((node) => node.title).join(' › ');
  String get errorMessage =>
      _failure ?? 'A hang nem indítható. Az Enter újrapróbálja.';

  Future<void> initialize() async {
    final generation = ++_generation;
    _speech.begin();
    _loading = true;
    _failure = null;
    notifyListeners();
    try {
      await _speech.audio.initialize(AudioCues.speechAssets);
      final catalog = await _content.loadMenu();
      await _speech.audio.initialize(
        catalog.allNodes.map((node) => node.audioAsset),
      );
      if (_disposed || generation != _generation) return;
      _catalog = catalog;
      _path
        ..clear()
        ..add(catalog.root);
      _selections
        ..clear()
        ..add(0);
      _loading = false;
      notifyListeners();
      _say([
        AudioCues.menuWelcome,
        menu.audioAsset,
        menu.children[selectedIndex].audioAsset,
      ]);
    } catch (error) {
      _contentFailed(error, generation);
    }
  }

  void moveSelection(int delta) {
    if (page != AppPage.menu) return;
    final index = (selectedIndex + delta).clamp(0, menu.children.length - 1);
    if (_activityMenu != null) {
      _sessionSelection = index;
    } else {
      _selections[_selections.length - 1] = index;
    }
    notifyListeners();
    repeat();
  }

  void activateIndex(int index) {
    if (page != AppPage.menu || index < 0 || index >= menu.children.length) {
      return;
    }
    if (_activityMenu != null) {
      _sessionSelection = index;
    } else {
      _selections[_selections.length - 1] = index;
    }
    activate();
  }

  void activate() {
    if (page != AppPage.menu) return;
    final entry = menu.children[selectedIndex];
    if (entry.children.isNotEmpty) {
      _path.add(entry);
      _selections.add(0);
      notifyListeners();
      _announceMenu();
    } else if (entry.activity != null) {
      unawaited(_openActivity(entry.activity!));
    } else {
      switch (entry.command!) {
        case MenuCommand.resume:
          _typing?.togglePause();
          _teaching?.resume();
        case MenuCommand.restart:
          _typing?.start();
          _teaching?.start();
        case MenuCommand.menu:
          returnToMenu();
        case MenuCommand.nextExercise:
        case MenuCommand.nextLesson:
          final route = _nextLessonActivity;
          if (route == null) return;
          _path.clear();
          _selections
            ..clear()
            ..addAll(route);
          var node = _catalog!.root;
          for (final selection in route) {
            _path.add(node);
            node = node.children[selection];
          }
          unawaited(_openActivity(node.activity!));
      }
    }
  }

  void back() {
    if (_activityMenu != null) {
      if (activityPhase == ExercisePhase.paused) {
        _typing?.togglePause();
        _teaching?.resume();
      } else {
        returnToMenu();
      }
    } else if (page == AppPage.menu) {
      if (_path.length > 1) {
        _path.removeLast();
        _selections.removeLast();
      }
      notifyListeners();
      _announceMenu();
    } else if (page == AppPage.error && _catalog != null) {
      returnToMenu();
    }
  }

  Future<void> _openActivity(ActivityReference reference) async {
    final generation = ++_generation;
    _disposeActivity();
    _speech.begin();
    _loading = true;
    _failure = null;
    notifyListeners();
    try {
      final exercise = await _content.loadExercise(reference);
      if (_disposed || generation != _generation) return;
      switch (exercise) {
        case TypingExercise():
          _typing = TypingController(
            exercise: exercise,
            speech: _speech,
            mode: _mode,
            countdownInterval: countdownInterval,
          )..addListener(_activityChanged);
          await _typing!.initialize();
        case LetterExercise():
          _teaching = LetterTeachingController(
            exercise: exercise,
            speech: _speech,
          )..addListener(_activityChanged);
          await _teaching!.initialize();
      }
      if (_disposed || generation != _generation) return;
      _loading = false;
      notifyListeners();
    } catch (error) {
      _contentFailed(error, generation);
    }
  }

  void _activityChanged() {
    if (_disposed) return;
    if (_typing != null) _mode = _typing!.mode;
    final phase = activityPhase;
    if (phase == ExercisePhase.ready || phase == ExercisePhase.error) {
      _loading = false;
    }
    final changed = phase != _lastPhase;
    _lastPhase = phase;
    if (changed && _activityMenu != null) _sessionSelection = 0;
    notifyListeners();
    if (changed && phase == ExercisePhase.paused) _announceMenu();
  }

  void pauseActivity() {
    _typing?.pause();
    _teaching?.pause();
  }

  void onKeyDown() => _typing?.cancelSpelling();
  void spell() => _typing?.spellEnteredLetters();
  void repeat() {
    if (page == AppPage.menu) {
      _say([menu.children[selectedIndex].audioAsset]);
    } else {
      _typing?.repeatWord();
      _teaching?.repeatInstruction();
    }
  }

  void toggleMode() {
    if (_loading || page == AppPage.error) return;
    if (_typing != null) {
      _typing!.toggleMode();
      _mode = _typing!.mode;
    } else {
      _mode = _mode == TypingMode.simple
          ? TypingMode.advanced
          : TypingMode.simple;
      if (_teaching != null) {
        _teaching!.announceMode(_mode);
      } else {
        _say([
          _mode == TypingMode.simple
              ? AudioCues.modeSimple
              : AudioCues.modeAdvanced,
        ]);
      }
    }
    notifyListeners();
  }

  void returnToMenu() {
    ++_generation;
    _disposeActivity();
    _loading = false;
    _failure = null;
    notifyListeners();
    _announceMenu();
  }

  void _disposeActivity() {
    _typing?.removeListener(_activityChanged);
    _teaching?.removeListener(_activityChanged);
    _typing?.dispose();
    _teaching?.dispose();
    _typing = null;
    _teaching = null;
    _lastPhase = null;
  }

  Future<void> retry() async {
    if (_typing == null && _teaching == null) {
      await initialize();
      return;
    }
    _loading = true;
    _failure = null;
    notifyListeners();
    if (_typing != null) await _typing!.initialize();
    if (_teaching != null) await _teaching!.initialize();
    if (_disposed) return;
    _loading = false;
    notifyListeners();
  }

  void _announceMenu() {
    if (_catalog == null || page != AppPage.menu) return;
    _say([menu.audioAsset, menu.children[selectedIndex].audioAsset]);
  }

  void _say(List<String> assets) {
    final token = _speech.begin();
    unawaited(
      _speech.sequence(token, assets).catchError((Object error) {
        if (_disposed || !_speech.isCurrent(token)) return;
        debugPrint('Audio failed: $error');
        _failure = 'A hang nem indítható. Az Enter újrapróbálja.';
        notifyListeners();
      }),
    );
  }

  void _contentFailed(Object error, int generation) {
    if (_disposed || generation != _generation) return;
    debugPrint('Content loading failed: $error');
    _loading = false;
    _failure =
        'A tartalom nem tölthető be. Enter: újrapróbálás. Escape: vissza.';
    notifyListeners();
    _say([AudioCues.contentError]);
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _disposeActivity();
    _speech.begin();
    unawaited(_speech.audio.dispose());
    super.dispose();
  }
}
