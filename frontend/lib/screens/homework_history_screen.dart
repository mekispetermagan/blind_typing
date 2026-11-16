import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/homework_repository.dart';
import '../services/homework_speech.dart';
import '../services/speech_coordinator.dart';
import '../widgets/app_keyboard.dart';
import '../widgets/progress/bar_charts.dart';

class HomeworkHistoryScreen extends StatefulWidget {
  const HomeworkHistoryScreen({
    required this.homework,
    required this.speech,
    required this.onBack,
    required this.onClose,
    super.key,
  });
  final HomeworkData homework;
  final SpeechCoordinator speech;
  final VoidCallback onBack;
  final VoidCallback onClose;
  @override
  State<HomeworkHistoryScreen> createState() => _HomeworkHistoryScreenState();
}

class _HomeworkHistoryScreenState extends State<HomeworkHistoryScreen> {
  int selected = 0;
  bool ready = false;
  bool loading = true;
  bool failed = false;
  late final keys = [
    for (final _ in widget.homework.attempts) GlobalKey(),
    GlobalKey(),
  ];
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      await widget.speech.audio.initialize([
        'assets/audio/homework_local_loading.wav',
        'assets/audio/homework_local_failure.wav',
      ]);
      if (!mounted) return;
      ready = true;
      _say(['assets/audio/homework_local_loading.wav']);
      await widget.speech.audio.initialize([
        homeworkCue('attempts_help'),
        homeworkCue('return'),
        for (final attempt in widget.homework.attempts)
          ...attemptAudio(attempt),
      ]);
      if (!mounted) return;
      setState(() => loading = false);
      _say([homeworkCue('attempts_help'), ..._current]);
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          failed = true;
        });
        _say(['assets/audio/homework_local_failure.wav']);
      }
    }
  }

  List<String> get _current => selected == widget.homework.attempts.length
      ? [homeworkCue('return')]
      : attemptAudio(widget.homework.attempts[selected]);
  void _say(Iterable<String> clips) {
    if (!ready) return;
    final token = widget.speech.begin();
    unawaited(widget.speech.sequence(token, clips));
  }

  void _move(int delta, {bool first = false, bool last = false}) {
    if (loading || failed) return;
    setState(
      () => selected = first
          ? 0
          : last
          ? widget.homework.attempts.length
          : (selected + delta).clamp(0, widget.homework.attempts.length),
    );
    _say(_current);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = keys[selected].currentContext;
      if (target != null) {
        unawaited(Scrollable.ensureVisible(target, alignment: .1));
      }
    });
  }

  void _back() {
    widget.speech.begin();
    widget.onBack();
  }

  @override
  void dispose() {
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
      LogicalKeyboardKey.escape: _back,
      LogicalKeyboardKey.arrowLeft: _back,
      LogicalKeyboardKey.f1: () => _say(
        loading
            ? ['assets/audio/homework_local_loading.wav']
            : failed
            ? ['assets/audio/homework_local_failure.wav']
            : _current,
      ),
      LogicalKeyboardKey.enter: () {
        if (failed) {
          unawaited(_initialize());
          return;
        }
        if (!loading && selected == widget.homework.attempts.length) _back();
      },
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Beadások')),
      body: loading
          ? const Center(child: Text('Beadások betöltése…'))
          : failed
          ? const Center(
              child: Text('A beadások nem tölthetők be. Enter: újrapróbálás.'),
            )
          : ListView(
              padding: const EdgeInsets.all(24),
              children: [
                for (var i = 0; i < widget.homework.attempts.length; i++)
                  Card(
                    key: keys[i],
                    color: selected == i
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    child: InkWell(
                      onTap: () {
                        setState(() => selected = i);
                        _say(_current);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              dateText(widget.homework.attempts[i].submittedAt),
                            ),
                            Text(
                              'Idő: ${widget.homework.attempts[i].durationMs ~/ 1000} mp · Hibák: ${widget.homework.attempts[i].mistakes} · Pontszám: ${widget.homework.attempts[i].score ?? '-'}',
                            ),
                            if (widget.homework.attempts[i].keys.isNotEmpty)
                              LetterStatisticsChart(
                                keysData: widget.homework.attempts[i].keys,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ListTile(
                  key: keys.last,
                  selected: selected == widget.homework.attempts.length,
                  title: const Text('Vissza'),
                  onTap: _back,
                ),
                const Text('↑ ↓: választás   F1: ismétlés   Escape: vissza'),
              ],
            ),
    ),
  );
}
