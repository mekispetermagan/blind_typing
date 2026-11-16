import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/progress_repository.dart';
import '../api/trainer_repository.dart';
import '../models/progress_navigation.dart';
import '../services/audio_service.dart';
import '../services/speech_coordinator.dart';
import '../widgets/progress/bar_charts.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({
    super.key,
    this.loadProgress,
    this.onBack,
    this.onClose,
    this.speech,
    this.activityAudio = const {},
    this.student,
    this.loadActivityAudio,
  });
  final Future<StudentProgress> Function()? loadProgress;
  final VoidCallback? onBack;
  final VoidCallback? onClose;
  final SpeechCoordinator? speech;
  final Map<String, List<String>> activityAudio;
  final TrainerStudent? student;
  final Future<Map<String, List<String>>> Function()? loadActivityAudio;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late Future<StudentProgress> _progress;
  ProgressNavigation? _navigation;
  List<List<GlobalKey>> _itemKeys = [];
  int _sectionIndex = 0;
  int _itemIndex = 0;
  int _generation = 0;
  bool _busy = true;
  bool _failed = false;
  bool _localReady = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final generation = ++_generation;
    _busy = true;
    _failed = false;
    _navigation = null;
    _progress = _fetch(generation);
  }

  Future<StudentProgress> _fetch(int generation) async {
    try {
      final speech = widget.speech;
      if (speech != null) {
        await speech.audio.initialize([
          AudioCues.progressLoading,
          AudioCues.progressFailure,
        ]);
        if (!mounted || generation != _generation) {
          throw StateError('Progress closed');
        }
        _localReady = true;
        _say([AudioCues.progressLoading]);
      }
      final progress =
          await (widget.loadProgress?.call() ??
              ProgressRepository().load(studentId: widget.student?.id));
      final activityAudio =
          await (widget.loadActivityAudio?.call() ??
              Future.value(widget.activityAudio));
      if (!mounted || generation != _generation) return progress;
      final navigation = ProgressNavigation(
        progress,
        DateTime.now(),
        activityAudio,
        backTitle: widget.student == null
            ? 'Vissza a főmenübe'
            : 'Vissza a tanulókhoz',
        backAudio: widget.student == null
            ? progressCue('return_main')
            : progressCue('return_students'),
      );
      if (speech != null) {
        await speech.audio.initialize([
          ...navigation.allAudio,
          if (widget.student case final student?) ...student.nameAudio,
        ]);
      }
      if (!mounted || generation != _generation) return progress;
      _navigation = navigation;
      _sectionIndex = 0;
      _itemIndex = 0;
      _itemKeys = [
        for (final section in navigation.sections)
          [for (final _ in section.items) GlobalKey()],
      ];
      _busy = false;
      if (speech != null) {
        _say([
          if (widget.student case final student?) ...student.nameAudio,
          progressCue('help'),
          navigation.sections.first.audio,
          ...navigation.sections.first.items.first.audio,
        ]);
      }
      return progress;
    } catch (_) {
      if (mounted && generation == _generation) {
        _busy = false;
        _failed = true;
        if (_localReady) _say([AudioCues.progressFailure]);
      }
      rethrow;
    }
  }

  void _say(Iterable<String> assets) {
    final speech = widget.speech;
    if (speech == null) return;
    final token = speech.begin();
    unawaited(
      speech.sequence(token, assets).catchError((Object error) {
        debugPrint('Progress speech failed: $error');
      }),
    );
  }

  void _repeat() {
    if (!_localReady) return;
    if (_busy) {
      _say([AudioCues.progressLoading]);
    } else if (_failed) {
      _say([AudioCues.progressFailure]);
    } else if (_navigation case final navigation?) {
      _say(navigation.sections[_sectionIndex].items[_itemIndex].audio);
    }
  }

  void _moveSection(int delta) {
    final navigation = _navigation;
    if (_busy || _failed || navigation == null) return;
    final next = (_sectionIndex + delta).clamp(
      0,
      navigation.sections.length - 1,
    );
    if (next == _sectionIndex) return;
    setState(() {
      _sectionIndex = next;
      _itemIndex = 0;
    });
    final section = navigation.sections[_sectionIndex];
    final firstAudio = section.items.first.audio;
    _say(
      firstAudio.length == 1 && firstAudio.first == section.audio
          ? firstAudio
          : [section.audio, ...firstAudio],
    );
    _scrollToSelection();
  }

  void _moveItem(int delta, {bool first = false, bool last = false}) {
    final navigation = _navigation;
    if (_busy || _failed || navigation == null) return;
    final items = navigation.sections[_sectionIndex].items;
    final next = first
        ? 0
        : last
        ? items.length - 1
        : (_itemIndex + delta).clamp(0, items.length - 1);
    if (next == _itemIndex) return;
    setState(() => _itemIndex = next);
    _say(items[next].audio);
    _scrollToSelection();
  }

  void _scrollToSelection() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _itemKeys.isEmpty) return;
      final context = _itemKeys[_sectionIndex][_itemIndex].currentContext;
      if (context != null) {
        unawaited(
          Scrollable.ensureVisible(
            context,
            duration: const Duration(milliseconds: 150),
            alignment: 0.25,
          ),
        );
      }
    });
  }

  void _leave() {
    ++_generation;
    widget.speech?.begin();
    widget.onBack?.call();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && widget.onBack != null) {
      _leave();
    } else if ((key == LogicalKeyboardKey.f4 ||
            (HardwareKeyboard.instance.isControlPressed &&
                key == LogicalKeyboardKey.keyW)) &&
        widget.onClose != null) {
      ++_generation;
      widget.speech?.begin();
      widget.onClose!();
    } else if (key == LogicalKeyboardKey.f1) {
      _repeat();
    } else if (key == LogicalKeyboardKey.enter && _failed) {
      setState(_load);
    } else if (key == LogicalKeyboardKey.enter &&
        !_busy &&
        _navigation != null &&
        _sectionIndex == _navigation!.sections.length - 1 &&
        widget.onBack != null) {
      _leave();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _moveSection(-1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _moveSection(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _moveItem(-1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _moveItem(1);
    } else if (key == LogicalKeyboardKey.home) {
      _moveItem(0, first: true);
    } else if (key == LogicalKeyboardKey.end) {
      _moveItem(0, last: true);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    ++_generation;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: _onKey,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.student == null
              ? 'Haladásom'
              : '${widget.student!.name} – Haladás',
        ),
        leading: widget.onBack == null
            ? null
            : IconButton(
                onPressed: _leave,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Vissza',
              ),
      ),
      body: FutureBuilder<StudentProgress>(
        future: _progress,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Haladási adatok betöltése…'),
                ],
              ),
            );
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'A haladási adatok nem tölthetők be. Enter: újrapróbálás. Escape: vissza.',
                  ),
                  TextButton(
                    onPressed: () => setState(_load),
                    child: const Text('Újrapróbálás'),
                  ),
                ],
              ),
            );
          }
          final navigation = _navigation!;
          final sections = navigation.sections;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      snapshot.data!.name,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    _section(context, sections[0].title),
                    for (var i = 0; i < sections[0].items.length; i++)
                      _item(0, i),
                    const SizedBox(height: 24),
                    _section(context, sections[1].title),
                    const Text(
                      'Az elmúlt 7 nap: elkezdett feladatok nap szerint',
                    ),
                    WeeklyActivityChart(days: navigation.summary.days),
                    const SizedBox(height: 16),
                    for (var i = 0; i < 7; i++) _item(1, i),
                    const Text('Heti összesítés: befejezett feladatok'),
                    for (var i = 7; i < sections[1].items.length; i++)
                      _item(1, i),
                    const SizedBox(height: 24),
                    _section(context, sections[2].title),
                    const Text(
                      'Első próbálkozásra helyes és hibás találatok; minden befejezett vagy megszakított feladatból.',
                    ),
                    if (navigation.summary.keys.isNotEmpty)
                      LetterStatisticsChart(keysData: navigation.summary.keys),
                    for (var i = 0; i < sections[2].items.length; i++)
                      _item(2, i),
                    const SizedBox(height: 24),
                    _section(context, sections[3].title),
                    for (var i = 0; i < sections[3].items.length; i++)
                      _item(3, i),
                    const SizedBox(height: 24),
                    for (
                      var section = 4;
                      section < sections.length;
                      section++
                    ) ...[
                      if (section < sections.length - 1)
                        _section(context, sections[section].title),
                      for (
                        var item = 0;
                        item < sections[section].items.length;
                        item++
                      )
                        _item(section, item),
                      if (section < sections.length - 1)
                        const SizedBox(height: 24),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _item(int section, int index) {
    final item = _navigation!.sections[section].items[index];
    return ListTile(
      key: _itemKeys[section][index],
      dense: true,
      selected: _sectionIndex == section && _itemIndex == index,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      title: Text(item.title),
      subtitle: item.subtitle == null ? null : Text(item.subtitle!),
      trailing: section == _navigation!.sections.length - 1
          ? const Icon(Icons.arrow_back)
          : item.trailing == null
          ? null
          : Text(item.trailing!),
      onTap: () {
        if (section == _navigation!.sections.length - 1 &&
            widget.onBack != null) {
          _leave();
          return;
        }
        setState(() {
          _sectionIndex = section;
          _itemIndex = index;
        });
        _say(item.audio);
      },
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
  );
}
