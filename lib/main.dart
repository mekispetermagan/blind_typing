import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'controllers/typing_controller.dart';
import 'models/sentence.dart';
import 'services/soloud_audio_service.dart';
import 'widgets/typing_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TypingApp());
}

class TypingApp extends StatefulWidget {
  const TypingApp({super.key});

  @override
  State<TypingApp> createState() => _TypingAppState();
}

class _TypingAppState extends State<TypingApp> with WidgetsBindingObserver {
  late final TypingController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = TypingController(
      sentences: sampleSentences,
      audio: SoloudAudioService(),
    );
    unawaited(_controller.initialize());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
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
        listenable: _controller,
        builder: (context, _) => TypingScreen(
          sentence: _controller.sentence,
          sentenceIndex: _controller.sentenceIndex,
          sentenceCount: _controller.sentenceCount,
          wordIndex: _controller.wordIndex,
          letterIndex: _controller.letterIndex,
          phase: _controller.phase,
          countdown: _controller.countdown,
          onStart: _controller.start,
          onCharacter: _controller.typeCharacter,
          onRepeat: _controller.repeatWord,
          onPause: _controller.togglePause,
          onClose: () => SystemNavigator.pop(),
        ),
      ),
    );
  }
}
