import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api/attempt_sync.dart';
import '../api/homework_repository.dart';
import '../controllers/typing_controller.dart';
import '../managers/practice_attempt.dart';
import '../models/exercise.dart';
import '../models/menu.dart';
import '../models/typing_state.dart';
import '../services/homework_speech.dart';
import '../services/practice_records.dart';
import '../services/speech_coordinator.dart';
import 'menu_screen.dart';
import 'status_screen.dart';
import 'typing_screen.dart';

class HomeworkPracticeScreen extends StatefulWidget {
  const HomeworkPracticeScreen({
    required this.homework,
    required this.speech,
    required this.records,
    required this.onAttempt,
    required this.onBack,
    required this.onMain,
    required this.onClose,
    this.events,
    this.repository,
    super.key,
  });
  final HomeworkData homework;
  final SpeechCoordinator speech;
  final PracticeRecords records;
  final AttemptSnapshotSink? onAttempt;
  final VoidCallback onBack;
  final VoidCallback onMain;
  final VoidCallback onClose;
  final ValueListenable<HomeworkSyncEvent?>? events;
  final HomeworkRepository? repository;
  @override
  State<HomeworkPracticeScreen> createState() => _HomeworkPracticeScreenState();
}

class _HomeworkPracticeScreenState extends State<HomeworkPracticeScreen> {
  TypingController? typing;
  bool loading = true;
  String? failure;
  String submission = '';
  int selected = 0;
  int generation = 0;
  ExercisePhase? previousPhase;

  @override
  void initState() {
    super.initState();
    widget.events?.addListener(_event);
    unawaited(_load());
  }

  Future<void> _load() async {
    final run = ++generation;
    setState(() {
      loading = true;
      failure = null;
    });
    try {
      await widget.speech.audio.initialize([
        homeworkCue('start_expired'),
        homeworkCue('completion_pending'),
        homeworkCue('completion_saved'),
        homeworkCue('completion_expired'),
        homeworkCue('try_again'),
        homeworkCue('back_list'),
        homeworkCue('back_main'),
        'assets/audio/menu_resume.wav',
        'assets/audio/menu_pause_restart.wav',
      ]);
      final data = await (widget.repository ?? HomeworkRepository()).load(
        widget.homework.id,
      );
      if (!mounted || run != generation) return;
      if (data.expired || !DateTime.now().isBefore(data.deadline)) {
        setState(() {
          loading = false;
          failure = 'A határidő lejárt. A feladat nem adható be.';
        });
        _say([homeworkCue('start_expired')]);
        return;
      }
      final exercise =
          ExerciseDefinition.fromJson(data.exercise!) as TypingExercise;
      final next = TypingController(
        exercise: exercise,
        speech: widget.speech,
        records: widget.records,
        onAttempt: widget.onAttempt,
      )..addListener(_changed);
      typing = next;
      await next.initialize();
      if (!mounted || run != generation) return;
      setState(() => loading = false);
    } catch (_) {
      if (!mounted || run != generation) return;
      setState(() {
        loading = false;
        failure = 'A házi feladat nem tölthető be. Enter: újrapróbálás. Escape: vissza.';
      });
      _say(['assets/audio/homework_local_failure.wav']);
    }
  }

  void _say(Iterable<String> clips) {
    final token = widget.speech.begin();
    unawaited(widget.speech.sequence(token, clips));
  }

  void _changed() {
    if (!mounted) return;
    final phase = typing?.phase;
    if (phase != previousPhase &&
        (phase == ExercisePhase.paused || phase == ExercisePhase.complete)) {
      selected = 0;
      if (phase == ExercisePhase.paused)
        _say(['assets/audio/paused.wav', 'assets/audio/menu_resume.wav']);
    }
    previousPhase = phase;
    setState(() {});
  }

  void _event() {
    final event = widget.events?.value;
    if (event == null || event.attemptId != typing?.lastAttemptId) return;
    setState(() => submission = event.status);
    if (event.status == 'pending' ||
        event.status == 'saved' ||
        event.status == 'expired') {
      unawaited(_announceResult(event));
    }
  }

  Future<void> _announceResult(HomeworkSyncEvent event) async {
    await Future<void>.delayed(Duration.zero);
    final announcement = typing?.completionAnnouncement;
    if (announcement != null) await announcement;
    if (!mounted || widget.events?.value != event) return;
    final cue = switch (event.status) {
      'saved' => 'completion_saved',
      'expired' => 'completion_expired',
      _ => 'completion_pending',
    };
    _say([homeworkCue(cue), homeworkCue('try_again')]);
  }

  Future<void> _restart() async {
    try {
      final data = await (widget.repository ?? HomeworkRepository()).load(
        widget.homework.id,
      );
      if (!mounted) return;
      if (data.expired || !DateTime.now().isBefore(data.deadline)) {
        _say([homeworkCue('start_expired')]);
        return;
      }
      submission = '';
      selected = 0;
      typing!.start();
    } catch (_) {
      _say(['assets/audio/homework_local_failure.wav']);
    }
  }

  void _move(int delta) {
    setState(() => selected = (selected + delta).clamp(0, 2));
    _repeat();
  }

  void _repeat() {
    final paused = typing?.phase == ExercisePhase.paused;
    final clips = paused
        ? [
            'assets/audio/menu_resume.wav',
            'assets/audio/menu_pause_restart.wav',
            homeworkCue('back_list'),
          ]
        : [
            homeworkCue('try_again'),
            homeworkCue('back_list'),
            homeworkCue('back_main'),
          ];
    _say([clips[selected]]);
  }

  void _activate() {
    if (typing?.phase == ExercisePhase.paused) {
      if (selected == 0) {
        typing!.togglePause();
      } else if (selected == 1) {
        unawaited(_restart());
      } else {
        widget.onBack();
      }
    } else if (selected == 0) {
      unawaited(_restart());
    } else if (selected == 1) {
      widget.onBack();
    } else {
      widget.onMain();
    }
  }

  void _select(int index) {
    setState(() => selected = index);
    _activate();
  }

  @override
  void dispose() {
    ++generation;
    widget.events?.removeListener(_event);
    typing?.removeListener(_changed);
    typing?.dispose();
    widget.speech.begin();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading)
      return StatusScreen(
        message: 'Házi feladat betöltése…',
        onClose: widget.onClose,
        onBack: widget.onBack,
      );
    if (failure != null)
      return StatusScreen(
        message: failure!,
        onClose: widget.onClose,
        onBack: widget.onBack,
        onRetry: _load,
      );
    final current = typing!;
    if (current.phase == ExercisePhase.paused ||
        current.phase == ExercisePhase.complete) {
      final paused = current.phase == ExercisePhase.paused;
      final titles = paused
          ? ['Folytatás', 'Újrakezdés', 'Vissza a házi feladatokhoz']
          : ['Újrapróbálás', 'Vissza a házi feladatokhoz', 'Vissza a főmenübe'];
      final nodes = [
        for (var i = 0; i < titles.length; i++)
          MenuNode(
            id: 'homework_option_$i',
            title: titles[i],
            command: MenuCommand.menu,
          ),
      ];
      return MenuScreen(
        title: paused ? 'Szünet' : 'Kész a házi feladat',
        breadcrumb: 'Házi feladat',
        summary: paused
            ? null
            : switch (submission) {
                'saved' => 'Beadva',
                'expired' => 'A beadás lejárt',
                'pending' => 'A beadás folyamatban van',
                _ => null,
              },
        items: nodes,
        selectedIndex: selected,
        mode: current.mode,
        onMove: _move,
        onActivate: _activate,
        onActivateIndex: _select,
        onBack: paused ? current.togglePause : widget.onBack,
        onRepeat: _repeat,
        onToggleMode: current.toggleMode,
        onClose: widget.onClose,
      );
    }
    return TypingScreen(
      title: 'Házi feladat',
      showSentence: true,
      sentence: current.sentence,
      sentenceIndex: current.sentenceIndex,
      sentenceCount: current.sentenceCount,
      wordIndex: current.wordIndex,
      letterIndex: current.letterIndex,
      enteredCharacters: current.enteredCharacters,
      mode: current.mode,
      phase: current.phase,
      countdown: current.countdown,
      onStart: current.start,
      onCharacter: current.typeCharacter,
      onRepeat: current.repeatWord,
      onSpell: current.spellEnteredLetters,
      onKeyDown: current.cancelSpelling,
      onToggleMode: current.toggleMode,
      onBackspace: current.backspace,
      onPause: current.pause,
      onClose: widget.onClose,
    );
  }
}
