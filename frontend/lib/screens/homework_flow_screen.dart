import 'package:flutter/material.dart';

import '../api/homework_repository.dart';
import '../api/trainer_repository.dart';
import '../controllers/app_controller.dart';
import 'homework_form_screen.dart';
import 'homework_history_screen.dart';
import 'homework_list_screen.dart';
import 'homework_practice_screen.dart';
import 'student_selection_screen.dart';

enum _Step { selectStudent, form, list, history, reopen, practice }

class HomeworkFlowScreen extends StatefulWidget {
  const HomeworkFlowScreen({
    required this.controller,
    required this.onClose,
    super.key,
  });
  final AppController controller;
  final VoidCallback onClose;
  @override
  State<HomeworkFlowScreen> createState() => _HomeworkFlowScreenState();
}

class _HomeworkFlowScreenState extends State<HomeworkFlowScreen> {
  late final HomeworkFlowKind kind = widget.controller.homeworkFlow!;
  late _Step step = kind == HomeworkFlowKind.student
      ? _Step.list
      : _Step.selectStudent;
  TrainerStudent? student;
  HomeworkData? homework;
  void _back() {
    setState(() {
      switch (step) {
        case _Step.selectStudent:
          widget.controller.back();
        case _Step.form:
          step = _Step.selectStudent;
        case _Step.list:
          if (kind == HomeworkFlowKind.student) {
            widget.controller.back();
          } else {
            step = _Step.selectStudent;
          }
        case _Step.history:
        case _Step.reopen:
          step = _Step.list;
        case _Step.practice:
          step = _Step.list;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    switch (step) {
      case _Step.selectStudent:
        return StudentSelectionScreen(
          speech: controller.progressSpeech,
          onSelect: (value) {
            setState(() {
              student = value;
              step = kind == HomeworkFlowKind.add ? _Step.form : _Step.list;
            });
          },
          initialStudentId: student?.id,
          onBack: _back,
          onClose: widget.onClose,
          title: kind == HomeworkFlowKind.add
              ? 'Házi feladat feladása'
              : 'Házi feladatok',
          selectionHelpAudio:
              'assets/audio/student_selection_homework_help.wav',
        );
      case _Step.form:
        return HomeworkFormScreen(
          speech: controller.progressSpeech,
          studentId: student!.id,
          student: student,
          onBack: _back,
          onSaved: () {
            setState(() => step = _Step.selectStudent);
          },
          onClose: widget.onClose,
        );
      case _Step.list:
        return HomeworkListScreen(
          speech: controller.progressSpeech,
          events: controller.homeworkEvents,
          studentId: kind == HomeworkFlowKind.student ? null : student!.id,
          student: student,
          onBack: _back,
          onClose: widget.onClose,
          onOpen: (value) {
            setState(() {
              homework = value;
              step = _Step.practice;
            });
          },
          onHistory: (value) {
            setState(() {
              homework = value;
              step = _Step.history;
            });
          },
          onReopen: (value) {
            setState(() {
              homework = value;
              step = _Step.reopen;
            });
          },
        );
      case _Step.history:
        return HomeworkHistoryScreen(
          homework: homework!,
          speech: controller.progressSpeech,
          onBack: _back,
          onClose: widget.onClose,
        );
      case _Step.reopen:
        return HomeworkFormScreen(
          homeworkId: homework!.id,
          student: student,
          speech: controller.progressSpeech,
          onBack: _back,
          onSaved: () {
            setState(() => step = _Step.list);
          },
          onClose: widget.onClose,
        );
      case _Step.practice:
        return HomeworkPracticeScreen(
          homework: homework!,
          speech: controller.progressSpeech,
          records: controller.practiceRecords,
          onAttempt: controller.onAttempt,
          events: controller.homeworkEvents,
          onBack: _back,
          onMain: controller.back,
          onClose: widget.onClose,
        );
    }
  }
}
