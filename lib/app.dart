import 'dart:async';

import 'package:flutter/material.dart';

import 'controllers/app_controller.dart';
import 'screens/menu_screen.dart';
import 'screens/status_screen.dart';
import 'screens/teaching_screen.dart';
import 'screens/typing_screen.dart';

class TypingApp extends StatefulWidget {
  const TypingApp({required this.controller, required this.onClose, super.key});
  final AppController controller;
  final VoidCallback onClose;
  @override
  State<TypingApp> createState() => _TypingAppState();
}

class _TypingAppState extends State<TypingApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.controller.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      widget.controller.pauseActivity();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Gépírás',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.teal,
        brightness: Brightness.dark,
      ),
      fontFamily: 'DejaVuSansMono',
    ),
    home: ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _ApplicationView(
        controller: widget.controller,
        onClose: widget.onClose,
      ),
    ),
  );
}

class _ApplicationView extends StatelessWidget {
  const _ApplicationView({required this.controller, required this.onClose});
  final AppController controller;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    switch (controller.page) {
      case AppPage.loading:
        return StatusScreen(message: 'Betöltés…', onClose: onClose);
      case AppPage.error:
        return StatusScreen(
          message: controller.errorMessage,
          onClose: onClose,
          onRetry: controller.retry,
          onBack: controller.back,
        );
      case AppPage.menu:
        return MenuScreen(
          title: controller.menu.title,
          breadcrumb: controller.breadcrumb,
          summary: controller.completionSummary,
          items: controller.menu.children,
          selectedIndex: controller.selectedIndex,
          mode: controller.mode,
          onMove: controller.moveSelection,
          onActivate: controller.activate,
          onActivateIndex: controller.activateIndex,
          onBack: controller.back,
          onRepeat: controller.repeat,
          onToggleMode: controller.toggleMode,
          onClose: onClose,
        );
      case AppPage.typing:
        final typing = controller.typing!;
        return TypingScreen(
          title: typing.exercise.title,
          showSentence: !typing.exercise.isWordDrill,
          sentence: typing.sentence,
          sentenceIndex: typing.sentenceIndex,
          sentenceCount: typing.sentenceCount,
          wordIndex: typing.wordIndex,
          letterIndex: typing.letterIndex,
          enteredCharacters: typing.enteredCharacters,
          mode: typing.mode,
          phase: typing.phase,
          countdown: typing.countdown,
          onStart: typing.start,
          onCharacter: typing.typeCharacter,
          onRepeat: typing.repeatWord,
          onSpell: typing.spellEnteredLetters,
          onKeyDown: typing.cancelSpelling,
          onToggleMode: controller.toggleMode,
          onBackspace: typing.backspace,
          onPause: controller.pauseActivity,
          onClose: onClose,
        );
      case AppPage.teaching:
        final teaching = controller.teaching!;
        return TeachingScreen(
          title: teaching.exercise.title,
          step: teaching.step,
          state: teaching.state,
          onStart: teaching.start,
          onCharacter: teaching.typeCharacter,
          onRepeat: teaching.repeatInstruction,
          onPause: controller.pauseActivity,
          onToggleMode: controller.toggleMode,
          onClose: onClose,
        );
    }
  }
}
