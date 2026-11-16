import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../api/homework_repository.dart';
import '../api/attempt_sync.dart';
import '../api/trainer_repository.dart';
import '../services/audio_service.dart';
import '../services/homework_speech.dart';
import '../services/practice_feedback.dart';
import '../services/speech_coordinator.dart';
import '../widgets/app_keyboard.dart';
import '../widgets/progress/bar_charts.dart';

class HomeworkListScreen extends StatefulWidget {
  const HomeworkListScreen({
    required this.speech,
    required this.onBack,
    required this.onClose,
    required this.onOpen,
    required this.onHistory,
    required this.onReopen,
    this.studentId,
    this.student,
    this.loadHomeworks,
    this.events,
    super.key,
  });
  final SpeechCoordinator speech;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final ValueChanged<HomeworkData> onOpen;
  final ValueChanged<HomeworkData> onHistory;
  final ValueChanged<HomeworkData> onReopen;
  final int? studentId;
  final TrainerStudent? student;
  final Future<List<HomeworkData>> Function()? loadHomeworks;
  final ValueListenable<HomeworkSyncEvent?>? events;
  @override
  State<HomeworkListScreen> createState() => _HomeworkListScreenState();
}

class _HomeworkListScreenState extends State<HomeworkListScreen> {
  List<HomeworkData> homeworks = [];
  int selected = 0;
  int generation = 0;
  bool loading = true;
  bool failed = false;
  bool audioReady = false;
  List<GlobalKey> keys = [];
  Timer? deadlineTimer;
  bool get trainer => widget.studentId != null;
  @override
  void initState() {
    super.initState();
    widget.events?.addListener(_syncChanged);
    unawaited(_load());
  }

  void _syncChanged() {
    final event = widget.events?.value;
    if (mounted &&
        !trainer &&
        event != null &&
        (event.status == 'saved' || event.status == 'expired')) {
      unawaited(_load());
    }
  }

  void _say(Iterable<String> clips) {
    if (!audioReady) return;
    final token = widget.speech.begin();
    unawaited(
      widget.speech.sequence(token, clips).catchError((Object e) {
        debugPrint('Homework speech: $e');
      }),
    );
  }

  Future<void> _load() async {
    final run = ++generation;
    final priorId = !loading && selected < homeworks.length
        ? homeworks[selected].id
        : null;
    deadlineTimer?.cancel();
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      await widget.speech.audio.initialize([
        'assets/audio/homework_local_loading.wav',
        'assets/audio/homework_local_failure.wav',
      ]);
      if (!mounted || run != generation) return;
      audioReady = true;
      _say(['assets/audio/homework_local_loading.wav']);
      final data =
          await (widget.loadHomeworks?.call() ??
              HomeworkRepository().list(studentId: widget.studentId));
      await widget.speech.audio.initialize([
        homeworkCue(trainer ? 'trainer_list_help' : 'list_help'),
        homeworkCue('empty'),
        homeworkCue('return'),
        homeworkCue('start_expired'),
        ...PracticeFeedback.audioAssets,
        ...AudioCues.speechAssets,
        if (widget.student case final student?) ...student.nameAudio,
        for (var n = 1; n <= 12; n++) 'assets/audio/progress_month_$n.wav',
        'assets/audio/progress_date.wav',
        'assets/audio/progress_correct.wav',
        'assets/audio/progress_incorrect.wav',
        for (final item in data) ...homeworkAudio(item, trainer: trainer),
      ]);
      if (!mounted || run != generation) return;
      setState(() {
        homeworks = data;
        final prior = data.indexWhere((item) => item.id == priorId);
        selected = prior < 0 ? 0 : prior;
        keys = [for (var i = 0; i <= data.length; i++) GlobalKey()];
        loading = false;
      });
      final future =
          data
              .where((item) => item.deadline.isAfter(DateTime.now()))
              .map((item) => item.deadline)
              .toList()
            ..sort();
      if (future.isNotEmpty) {
        deadlineTimer = Timer(
          future.first.difference(DateTime.now()) +
              const Duration(milliseconds: 100),
          () => unawaited(_load()),
        );
      }
      _say([
        if (widget.student case final student?) ...student.nameAudio,
        homeworkCue(trainer ? 'trainer_list_help' : 'list_help'),
        if (data.isEmpty) homeworkCue('empty'),
        ..._currentAudio,
      ]);
    } catch (_) {
      if (!mounted || run != generation) return;
      setState(() {
        failed = true;
        loading = false;
      });
      _say(['assets/audio/homework_local_failure.wav']);
    }
  }

  List<String> get _currentAudio => selected == homeworks.length
      ? [homeworkCue('return')]
      : homeworkAudio(homeworks[selected], trainer: trainer);
  void _repeat() {
    if (loading) {
      _say(['assets/audio/homework_local_loading.wav']);
    } else if (failed) {
      _say(['assets/audio/homework_local_failure.wav']);
    } else {
      _say(_currentAudio);
    }
  }

  void _move(int delta, {bool first = false, bool last = false}) {
    if (loading || failed) return;
    setState(
      () => selected = first
          ? 0
          : last
          ? homeworks.length
          : (selected + delta).clamp(0, homeworks.length),
    );
    _repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = keys[selected].currentContext;
      if (target != null) {
        unawaited(Scrollable.ensureVisible(target, alignment: .1));
      }
    });
  }

  void _back() {
    ++generation;
    widget.speech.begin();
    widget.onBack();
  }

  void _activate() {
    if (loading) return;
    if (failed) {
      unawaited(_load());
      return;
    }
    if (selected == homeworks.length) {
      _back();
      return;
    }
    final item = homeworks[selected];
    if (trainer) {
      if (item.attempts.isNotEmpty) {
        widget.speech.begin();
        widget.onHistory(item);
      } else {
        _repeat();
      }
    } else if (item.expired || !DateTime.now().isBefore(item.deadline)) {
      _say([homeworkCue('start_expired')]);
    } else {
      widget.speech.begin();
      widget.onOpen(item);
    }
  }

  void _reopen() {
    if (!loading &&
        !failed &&
        trainer &&
        selected < homeworks.length &&
        homeworks[selected].expired) {
      widget.speech.begin();
      widget.onReopen(homeworks[selected]);
    }
  }

  @override
  void dispose() {
    deadlineTimer?.cancel();
    widget.events?.removeListener(_syncChanged);
    ++generation;
    widget.speech.begin();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppKeyboard(
    onClose: widget.onClose,
    shortcuts: {
      LogicalKeyboardKey.arrowUp: () => _move(-1),
      LogicalKeyboardKey.arrowDown: () => _move(1),
      LogicalKeyboardKey.home: () => _move(0, first: true),
      LogicalKeyboardKey.end: () => _move(0, last: true),
      LogicalKeyboardKey.enter: _activate,
      LogicalKeyboardKey.numpadEnter: _activate,
      LogicalKeyboardKey.arrowRight: _activate,
      LogicalKeyboardKey.escape: _back,
      LogicalKeyboardKey.arrowLeft: _back,
      LogicalKeyboardKey.f1: _repeat,
      LogicalKeyboardKey.keyR: _reopen,
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Házi feladatok')),
      body: loading
          ? const Center(child: Text('Házi feladatok betöltése…'))
          : failed
          ? const Center(
              child: Text(
                'A házi feladatok nem tölthetők be. Enter: újrapróbálás.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                if (widget.student case final student?)
                  Text('Tanuló: ${student.name}'),
                if (homeworks.isEmpty)
                  const Text('Nincs megjeleníthető házi feladat.'),
                for (var i = 0; i < homeworks.length; i++)
                  _card(homeworks[i], i),
                ListTile(
                  key: keys.isEmpty ? null : keys.last,
                  selected: selected == homeworks.length,
                  title: const Text('Vissza'),
                  onTap: _back,
                ),
                Text(
                  trainer
                      ? '↑ ↓: választás   Enter: korábbi beadások   R: újranyitás   F1: ismétlés   Escape: vissza'
                      : '↑ ↓: választás   Enter: megnyitás   F1: ismétlés   Escape: vissza',
                ),
              ],
            ),
    ),
  );
  Widget _card(HomeworkData item, int index) => Card(
    key: keys[index],
    color: selected == index
        ? Theme.of(context).colorScheme.primaryContainer
        : null,
    child: InkWell(
      onTap: () {
        setState(() => selected = index);
        _activate();
      },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Oktató: ${item.trainerName}'),
            Text('Határidő: ${dateText(item.deadline)}'),
            Text(homeworkStatus(item)),
            for (final entry in item.entries)
              Text('${entry.text} × ${entry.repetitions}'),
            if (trainer && item.attempts.isEmpty)
              const Text('Még nincs beadás'),
            if (trainer && item.attempts.isNotEmpty) ...[
              Text(
                'Legutóbbi beadás: ${dateText(item.attempts.first.submittedAt)}',
              ),
              Text(
                'Idő: ${item.attempts.first.durationMs ~/ 1000} mp · Hibák: ${item.attempts.first.mistakes} · Pontszám: ${item.attempts.first.score ?? '-'}',
              ),
              if (item.attempts.first.keys.isNotEmpty)
                LetterStatisticsChart(keysData: item.attempts.first.keys),
              TextButton(
                onPressed: () => widget.onHistory(item),
                child: const Text('Korábbi beadások megtekintése'),
              ),
            ],
            if (trainer && item.expired)
              TextButton(
                onPressed: () => widget.onReopen(item),
                child: const Text('Újranyitás új határidővel'),
              ),
          ],
        ),
      ),
    ),
  );
}
