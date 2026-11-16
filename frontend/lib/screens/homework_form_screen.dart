import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/homework_repository.dart';
import '../api/trainer_repository.dart';
import '../services/audio_service.dart';
import '../services/practice_feedback.dart';
import '../services/speech_coordinator.dart';
import '../widgets/app_keyboard.dart';

class HomeworkFormScreen extends StatefulWidget {
  const HomeworkFormScreen({
    required this.speech,
    required this.onBack,
    required this.onSaved,
    required this.onClose,
    this.studentId,
    this.student,
    this.homeworkId,
    this.repository,
    super.key,
  });
  final SpeechCoordinator speech;
  final VoidCallback onBack;
  final VoidCallback onSaved;
  final VoidCallback onClose;
  final int? studentId;
  final TrainerStudent? student;
  final String? homeworkId;
  final HomeworkRepository? repository;
  @override
  State<HomeworkFormScreen> createState() => _HomeworkFormScreenState();
}

class _EntryRow {
  final text = TextEditingController();
  final repetitions = TextEditingController(text: '1');
  final textFocus = FocusNode();
  final repetitionsFocus = FocusNode();
  void dispose() {
    text.dispose();
    repetitions.dispose();
    textFocus.dispose();
    repetitionsFocus.dispose();
  }
}

class _HomeworkFormScreenState extends State<HomeworkFormScreen> {
  final date = TextEditingController();
  final time = TextEditingController();
  final dateFocus = FocusNode();
  final timeFocus = FocusNode();
  final rows = <_EntryRow>[];
  final requestId = List.generate(
    16,
    (_) => Random.secure().nextInt(256),
  ).map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  bool loading = true;
  bool saving = false;
  String? error;
  String currentCue = 'homework_form_help';
  TextEditingController? currentField;
  int? currentRow;

  static const cues = [
    'homework_form_help',
    'homework_date',
    'homework_time',
    'homework_entry',
    'homework_row',
    'homework_repetitions',
    'homework_add_row',
    'homework_remove_row',
    'homework_submit',
    'homework_save_deadline',
    'homework_invalid',
    'homework_saving',
    'homework_created',
    'homework_local_failure',
    'homework_delete',
    'homework_space',
    'homework_punctuation',
    'homework_dot',
    'homework_comma',
    'homework_colon',
    'homework_dash',
    'homework_question',
    'homework_exclamation',
    'homework_semicolon',
    'homework_slash',
    'homework_open_paren',
    'homework_close_paren',
    'homework_quote',
    'homework_apostrophe',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final next = DateTime(
      now.year,
      now.month,
      now.day + 1,
      now.hour,
      now.minute,
    );
    date.text =
        '${next.year.toString().padLeft(4, '0')}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
    time.text =
        '${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}';
    dateFocus.addListener(() {
      if (dateFocus.hasFocus) _field('homework_date', date);
    });
    timeFocus.addListener(() {
      if (timeFocus.hasFocus) _field('homework_time', time);
    });
    if (widget.homeworkId == null) _addRow(notify: false);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await widget.speech.audio.initialize([
        ...cues.map(_clip),
        ...AudioCues.speechAssets,
        ...PracticeFeedback.audioAssets,
        if (widget.student case final student?) ...student.nameAudio,
      ]);
      if (!mounted) return;
      setState(() => loading = false);
      _say([
        if (widget.student case final student?) ...student.nameAudio,
        'assets/audio/homework_form_help.wav',
      ]);
    } catch (_) {
      if (mounted)
        setState(() {
          loading = false;
          error = 'A hangok nem tölthetők be.';
        });
    }
  }

  void _say(Iterable<String> assets) {
    if (loading) return;
    final token = widget.speech.begin();
    unawaited(
      widget.speech.sequence(token, assets).catchError((Object e) {
        debugPrint('Homework speech: $e');
      }),
    );
  }

  static String _clip(String cue) => switch (cue) {
    'homework_submit' => 'assets/audio/menu_add_homework.wav',
    'homework_dot' => 'assets/audio/reach_nt_nt_08_word_0.wav',
    _ => 'assets/audio/$cue.wav',
  };

  static const punctuation = {
    '.': 'dot',
    ',': 'comma',
    ':': 'colon',
    '-': 'dash',
    '?': 'question',
    '!': 'exclamation',
    ';': 'semicolon',
    '/': 'slash',
    '(': 'open_paren',
    ')': 'close_paren',
    '"': 'quote',
    "'": 'apostrophe',
  };
  List<String> _spell(String value) => [
    for (final char in value.split(''))
      char == ' '
          ? 'assets/audio/homework_space.wav'
          : RegExp(r'^[\p{L}\p{N}]$', unicode: true).hasMatch(char)
          ? AudioCues.letter(char)
          : _clip('homework_${punctuation[char] ?? 'punctuation'}'),
  ];

  void _field(String cue, TextEditingController field, {int? row}) {
    currentCue = cue;
    currentField = field;
    currentRow = row;
    _repeat();
  }

  void _repeat() => _say([
    if (currentRow case final index?) ...[
      'assets/audio/homework_row.wav',
      ...PracticeFeedback.number(index),
    ],
    _clip(currentCue),
    if (currentField != null) ..._spell(currentField!.text),
  ]);
  void _changed(String previous, String current) {
    if (current.length < previous.length) {
      _say(['assets/audio/homework_delete.wav']);
      return;
    }
    if (current.isNotEmpty && current != previous) {
      final inserted = currentField?.selection.baseOffset ?? current.length;
      final char = current[(inserted - 1).clamp(0, current.length - 1)];
      _say(_spell(char));
    }
  }

  void _addRow({bool notify = true}) {
    final row = _EntryRow();
    row.textFocus.addListener(() {
      if (row.textFocus.hasFocus)
        _field('homework_entry', row.text, row: rows.indexOf(row) + 1);
    });
    row.repetitionsFocus.addListener(() {
      if (row.repetitionsFocus.hasFocus)
        _field(
          'homework_repetitions',
          row.repetitions,
          row: rows.indexOf(row) + 1,
        );
    });
    if (notify) {
      setState(() => rows.add(row));
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => row.textFocus.requestFocus(),
      );
    } else {
      rows.add(row);
    }
  }

  void _removeRow(_EntryRow row) {
    if (rows.length == 1) {
      row.text.clear();
      row.repetitions.text = '1';
      row.textFocus.requestFocus();
      return;
    }
    setState(() => rows.remove(row));
    WidgetsBinding.instance.addPostFrameCallback((_) => row.dispose());
  }

  DateTime? _deadline() {
    final d = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date.text);
    final t = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(time.text);
    if (d == null || t == null) return null;
    final y = int.parse(d[1]!);
    final m = int.parse(d[2]!);
    final day = int.parse(d[3]!);
    final h = int.parse(t[1]!);
    final min = int.parse(t[2]!);
    final value = DateTime(y, m, day, h, min);
    if (value.year != y ||
        value.month != m ||
        value.day != day ||
        value.hour != h ||
        value.minute != min)
      return null;
    return value;
  }

  Future<void> _submit() async {
    if (saving || loading) return;
    final deadline = _deadline();
    final entries = <HomeworkEntryData>[];
    for (final row in rows) {
      final text = row.text.text.trim();
      if (text.isEmpty && rows.length > 1 && identical(row, rows.last))
        continue;
      final count = int.tryParse(row.repetitions.text);
      if (text.isEmpty ||
          count == null ||
          count < 1 ||
          !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(text)) {
        setState(() => error = 'Ellenőrizd a szöveget és az ismétlésszámot.');
        _say(['assets/audio/homework_invalid.wav']);
        return;
      }
      entries.add(HomeworkEntryData(text, count));
    }
    if (deadline == null ||
        deadline.difference(DateTime.now()) < const Duration(minutes: 60) ||
        (widget.homeworkId == null && entries.isEmpty)) {
      setState(
        () => error = 'A határidő legalább 60 perc múlva legyen, és minden sor legyen érvényes.',
      );
      _say(['assets/audio/homework_invalid.wav']);
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    _say(['assets/audio/homework_saving.wav']);
    try {
      final repository = widget.repository ?? HomeworkRepository();
      if (widget.homeworkId case final id?) {
        await repository.reopen(id, deadline);
      } else {
        await repository.create(
          widget.student?.id ?? widget.studentId!,
          deadline,
          entries,
          requestId: requestId,
        );
      }
      if (!mounted) return;
      await widget.speech.audio.initialize([
        'assets/audio/homework_created.wav',
      ]);
      final token = widget.speech.begin();
      await widget.speech.say(token, 'assets/audio/homework_created.wav');
      if (mounted) widget.onSaved();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        saving = false;
        error =
            'A feladat nem menthető. Ellenőrizd a kapcsolatot és a határidőt.';
      });
      _say(['assets/audio/homework_local_failure.wav']);
    }
  }

  @override
  void dispose() {
    widget.speech.begin();
    date.dispose();
    time.dispose();
    dateFocus.dispose();
    timeFocus.dispose();
    for (final row in rows) {
      row.dispose();
    }
    super.dispose();
  }

  Widget _input(
    TextEditingController controller,
    FocusNode focus,
    String label, {
    VoidCallback? submit,
    TextInputType? keyboardType,
  }) {
    var previous = controller.text;
    return TextField(
      enabled: !saving,
      controller: controller,
      focusNode: focus,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      onChanged: (value) {
        _changed(previous, value);
        previous = value;
      },
      onSubmitted: (_) => submit?.call(),
    );
  }

  Widget _button(String cue, Widget child) => Focus(
    onFocusChange: (focused) {
      if (focused) {
        currentCue = cue;
        currentField = null;
        currentRow = null;
        _repeat();
      }
    },
    child: child,
  );
  @override
  Widget build(BuildContext context) => AppKeyboard(
    onClose: widget.onClose,
    shortcuts: {
      LogicalKeyboardKey.escape: widget.onBack,
      LogicalKeyboardKey.f1: _repeat,
    },
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.homeworkId == null ? 'Házi feladat feladása' : 'Újranyitás',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.student case final student?)
              Text('Tanuló: ${student.name}'),
            _input(
              date,
              dateFocus,
              'Határidő dátuma (ÉÉÉÉ-HH-NN)',
              submit: () => timeFocus.requestFocus(),
            ),
            _input(
              time,
              timeFocus,
              'Határidő ideje (ÓÓ:PP)',
              submit: () {
                if (rows.isNotEmpty) rows.first.textFocus.requestFocus();
              },
            ),
            for (final (index, row) in rows.indexed) ...[
              const SizedBox(height: 20),
              Text('${index + 1}. sor'),
              _input(
                row.text,
                row.textFocus,
                'Gyakorlandó szöveg',
                submit: _addRow,
              ),
              _input(
                row.repetitions,
                row.repetitionsFocus,
                'Ismétlések száma',
                keyboardType: TextInputType.number,
                submit: _addRow,
              ),
              _button(
                'homework_remove_row',
                TextButton(
                  onPressed: saving ? null : () => _removeRow(row),
                  child: const Text('Sor törlése'),
                ),
              ),
            ],
            if (widget.homeworkId == null)
              _button(
                'homework_add_row',
                OutlinedButton(
                  onPressed: saving ? null : _addRow,
                  child: const Text('Új sor'),
                ),
              ),
            if (error != null) Text(error!),
            const SizedBox(height: 24),
            _button(
              widget.homeworkId == null
                  ? 'homework_submit'
                  : 'homework_save_deadline',
              FilledButton(
                onPressed: saving || loading ? null : _submit,
                child: Text(
                  saving
                      ? 'Mentés…'
                      : widget.homeworkId == null
                      ? 'Feladás'
                      : 'Új határidő mentése',
                ),
              ),
            ),
            TextButton(
              onPressed: saving ? null : widget.onBack,
              child: const Text('Vissza'),
            ),
          ],
        ),
      ),
    ),
  );
}
