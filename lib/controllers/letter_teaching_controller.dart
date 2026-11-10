import 'dart:async';

import 'package:flutter/foundation.dart';

import '../managers/letter_teaching_manager.dart';
import '../models/exercise.dart';
import '../models/teaching_state.dart';
import '../models/typing_state.dart';
import '../services/audio_service.dart';
import '../services/speech_coordinator.dart';

class LetterTeachingController extends ChangeNotifier {
  LetterTeachingController({
    required LetterExercise exercise,
    required this._speech,
  }) : _manager = LetterTeachingManager(exercise);
  final LetterTeachingManager _manager;
  final SpeechCoordinator _speech;
  bool _disposed = false;
  TeachingState get state => _manager.state;
  LetterStep get step => _manager.step;
  LetterExercise get exercise => _manager.exercise;

  Future<void> initialize() async {
    final token = _speech.begin();
    try {
      await _speech.audio.initialize([
        ...AudioCues.speechAssets,
        ...exercise.audioAssets,
      ]);
      if (_disposed || !_speech.isCurrent(token)) return;
      _manager.ready();
      notifyListeners();
      await _speech.say(token, AudioCues.teachingWelcome);
    } catch (_) {
      _fail(token);
    }
  }

  void start() {
    if (state.phase == ExercisePhase.error) {
      unawaited(initialize());
      return;
    }
    if (!_manager.restart()) return;
    notifyListeners();
    repeatInstruction();
  }

  void typeCharacter(String character) {
    final previous = step;
    final result = _manager.typeCharacter(character);
    if (result == TeachingResult.ignored) return;
    try {
      _speech.audio.feedback(correct: result != TeachingResult.incorrect);
      notifyListeners();
      switch (result) {
        case TeachingResult.incorrect:
          _say([
            AudioCues.wrongKeyPrefix,
            AudioCues.letter(character),
            AudioCues.wrongKeySuffix,
            step.audio('retry'),
          ]);
        case TeachingResult.accepted:
          _say([step.audio('success')]);
        case TeachingResult.stepAdvanced:
          unawaited(_advance(_speech.begin(), previous));
        case TeachingResult.completed:
          _say([previous.audio('complete'), AudioCues.complete]);
        case TeachingResult.ignored:
          break;
      }
    } catch (_) {
      _fail(_speech.begin());
    }
  }

  Future<void> _advance(int token, LetterStep previous) async {
    try {
      if (!await _speech.say(token, previous.audio('complete'))) return;
      _manager.beginStep();
      notifyListeners();
      await _speech.say(token, step.audio('instruction'));
    } catch (_) {
      _fail(token);
    }
  }

  void repeatInstruction() {
    if (state.phase == ExercisePhase.typing) _say([step.audio('instruction')]);
  }

  void announceMode(TypingMode mode) {
    final interruptedStep = state.phase == ExercisePhase.reading;
    if (interruptedStep) _manager.beginStep();
    _say([
      mode == TypingMode.simple ? AudioCues.modeSimple : AudioCues.modeAdvanced,
      if (interruptedStep) step.audio('instruction'),
    ]);
    notifyListeners();
  }

  void pause() {
    if (!_manager.pause()) return;
    _speech.begin();
    notifyListeners();
  }

  void resume() {
    if (!_manager.resume()) return;
    notifyListeners();
    repeatInstruction();
  }

  void _say(List<String> assets) {
    final token = _speech.begin();
    unawaited(
      _speech.sequence(token, assets).catchError((Object _) => _fail(token)),
    );
  }

  void _fail(int token) {
    if (_disposed || !_speech.isCurrent(token)) return;
    _speech.begin();
    _manager.fail();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _speech.begin();
    super.dispose();
  }
}
