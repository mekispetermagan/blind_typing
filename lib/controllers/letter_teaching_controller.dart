import 'dart:async';

import 'package:flutter/foundation.dart';

import '../managers/letter_teaching_manager.dart';
import '../managers/practice_attempt.dart';
import '../models/exercise.dart';
import '../models/teaching_state.dart';
import '../models/practice_result.dart';
import '../models/typing_state.dart';
import '../services/audio_service.dart';
import '../services/practice_feedback.dart';
import '../services/practice_records.dart';
import '../services/speech_coordinator.dart';

class LetterTeachingController extends ChangeNotifier {
  LetterTeachingController({
    required LetterExercise exercise,
    required this._speech,
    PracticeRecords? records,
  }) : _manager = LetterTeachingManager(exercise),
       _records = records ?? PracticeRecords();
  final LetterTeachingManager _manager;
  final SpeechCoordinator _speech;
  final PracticeRecords _records;
  PracticeAttempt? _attempt;
  PracticeResult? _practiceResult;
  bool _disposed = false;
  PracticeResult? get practiceResult => _practiceResult;
  TeachingState get state => _manager.state;
  LetterStep get step => _manager.step;
  LetterExercise get exercise => _manager.exercise;

  Future<void> initialize() async {
    final token = _speech.begin();
    try {
      await _speech.audio.initialize([
        ...AudioCues.speechAssets,
        ...exercise.audioAssets,
        ...PracticeFeedback.audioAssets,
      ]);
      if (_disposed || !_speech.isCurrent(token)) return;
      _manager.ready();
      _attempt = null;
      _practiceResult = null;
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
    _practiceResult = null;
    _attempt = PracticeAttempt();
    _syncAttemptClock();
    notifyListeners();
    repeatInstruction();
  }

  void typeCharacter(String character) {
    final previous = step;
    final result = _manager.typeCharacter(character);
    if (result == TeachingResult.ignored) return;
    if (result == TeachingResult.incorrect) _attempt!.recordError();
    _syncAttemptClock();
    if (result == TeachingResult.completed) {
      _practiceResult = _records.finish(exercise.id, _attempt!.finish());
      _attempt = null;
    }
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
          _say([
            previous.audio('complete'),
            ...PracticeFeedback.speech(_practiceResult!),
            AudioCues.complete,
          ]);
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
      _syncAttemptClock();
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
    if (interruptedStep) {
      _manager.beginStep();
      _syncAttemptClock();
    }
    _say([
      mode == TypingMode.simple ? AudioCues.modeSimple : AudioCues.modeAdvanced,
      if (interruptedStep) step.audio('instruction'),
    ]);
    notifyListeners();
  }

  void pause() {
    if (!_manager.pause()) return;
    _syncAttemptClock();
    _speech.begin();
    notifyListeners();
  }

  void resume() {
    if (!_manager.resume()) return;
    _syncAttemptClock();
    notifyListeners();
    repeatInstruction();
  }

  void _syncAttemptClock() =>
      _attempt?.setAcceptingInput(state.phase == ExercisePhase.typing);

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
    _syncAttemptClock();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _speech.begin();
    super.dispose();
  }
}
