import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/trainer_repository.dart';
import '../models/menu.dart';
import '../services/speech_coordinator.dart';
import '../widgets/app_keyboard.dart';
import '../widgets/menu_list.dart';

class StudentSelectionScreen extends StatefulWidget {
  const StudentSelectionScreen({
    required this.speech,
    required this.onSelect,
    required this.onBack,
    required this.onClose,
    this.initialStudentId,
    this.loadStudents,
    this.title = 'Tanulók haladása',
    this.selectionHelpAudio = 'assets/audio/student_selection_help.wav',
    super.key,
  });
  final SpeechCoordinator speech;
  final ValueChanged<TrainerStudent> onSelect;
  final VoidCallback onBack;
  final VoidCallback onClose;
  final int? initialStudentId;
  final Future<List<TrainerStudent>> Function()? loadStudents;
  final String title;
  final String selectionHelpAudio;

  @override
  State<StudentSelectionScreen> createState() => _StudentSelectionScreenState();
}

class _StudentSelectionScreenState extends State<StudentSelectionScreen> {
  static const loadingAudio = 'assets/audio/student_selection_loading.wav';
  static const failureAudio = 'assets/audio/student_selection_failure.wav';
  static const emptyAudio = 'assets/audio/student_selection_empty.wav';
  static const returnAudio = 'assets/audio/student_selection_return.wav';
  List<TrainerStudent> students = [];
  int selected = 0;
  int generation = 0;
  bool loading = true;
  bool failed = false;
  bool localReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  void _say(Iterable<String> clips) {
    final token = widget.speech.begin();
    unawaited(
      widget.speech.sequence(token, clips).catchError((Object error) {
        debugPrint('Student selection speech failed: $error');
      }),
    );
  }

  Future<void> _load() async {
    final request = ++generation;
    setState(() {
      loading = true;
      failed = false;
    });
    try {
      await widget.speech.audio.initialize([loadingAudio, failureAudio]);
      if (!mounted || request != generation) return;
      localReady = true;
      _say([loadingAudio]);
      final loaded =
          await (widget.loadStudents?.call() ?? TrainerRepository().students());
      await widget.speech.audio.initialize([
        widget.selectionHelpAudio,
        emptyAudio,
        returnAudio,
        for (final student in loaded) ...student.nameAudio,
      ]);
      if (!mounted || request != generation) return;
      final previous = loaded.indexWhere(
        (student) => student.id == widget.initialStudentId,
      );
      setState(() {
        students = loaded;
        selected = previous < 0 ? 0 : previous;
        loading = false;
      });
      _say([
        widget.selectionHelpAudio,
        if (students.isEmpty) emptyAudio,
        ..._selectedAudio,
      ]);
    } catch (_) {
      if (!mounted || request != generation) return;
      setState(() {
        loading = false;
        failed = true;
      });
      if (localReady) _say([failureAudio]);
    }
  }

  List<String> get _selectedAudio =>
      selected < students.length ? students[selected].nameAudio : [returnAudio];

  void _repeat() {
    if (!localReady) return;
    if (loading) {
      _say([loadingAudio]);
      return;
    }
    if (failed) {
      _say([failureAudio]);
      return;
    }
    _say(_selectedAudio);
  }

  void _move(int delta, {bool first = false, bool last = false}) {
    if (loading || failed) return;
    setState(
      () => selected = first
          ? 0
          : last
          ? students.length
          : (selected + delta).clamp(0, students.length),
    );
    _repeat();
  }

  void _back() {
    ++generation;
    widget.speech.begin();
    widget.onBack();
  }

  void _activate(int index) {
    if (loading) return;
    if (failed) {
      unawaited(_load());
      return;
    }
    if (index == students.length) {
      _back();
      return;
    }
    widget.speech.begin();
    widget.onSelect(students[index]);
  }

  @override
  void dispose() {
    ++generation;
    widget.speech.begin();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entries = [
      for (final student in students)
        MenuNode(
          id: 'student_${student.id}',
          title: student.name,
          command: MenuCommand.students,
        ),
      MenuNode(
        id: 'student_return',
        title: 'Vissza az oktatói főmenübe',
        command: MenuCommand.previous,
      ),
    ];
    return AppKeyboard(
      onClose: widget.onClose,
      shortcuts: {
        LogicalKeyboardKey.arrowUp: () => _move(-1),
        LogicalKeyboardKey.arrowDown: () => _move(1),
        LogicalKeyboardKey.home: () => _move(0, first: true),
        LogicalKeyboardKey.end: () => _move(0, last: true),
        LogicalKeyboardKey.enter: () => _activate(selected),
        LogicalKeyboardKey.numpadEnter: () => _activate(selected),
        LogicalKeyboardKey.arrowRight: () => _activate(selected),
        LogicalKeyboardKey.escape: _back,
        LogicalKeyboardKey.arrowLeft: _back,
        LogicalKeyboardKey.f1: _repeat,
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (loading)
                const Text('Tanulók betöltése…')
              else if (failed)
                const Text(
                  'A tanulók nem tölthetők be. Enter: újrapróbálás. Escape: vissza.',
                )
              else ...[
                if (students.isEmpty)
                  const Text('Nincsenek hozzád rendelt tanulók.')
                else
                  const Text(
                    'Válassz tanulót!',
                    style: TextStyle(fontSize: 24),
                  ),
                const SizedBox(height: 24),
                Expanded(
                  child: MenuList(
                    items: entries,
                    selectedIndex: selected,
                    onActivate: _activate,
                  ),
                ),
                const Text(
                  '↑ ↓: választás   Enter / →: megnyitás   Escape / ←: vissza\nHome / End: első / utolsó   F1: ismétlés',
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
