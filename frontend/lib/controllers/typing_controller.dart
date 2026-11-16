import 'dart:async';

import 'package:flutter/foundation.dart';

import '../managers/practice_attempt.dart';
import '../managers/typing_session_manager.dart';
import '../models/exercise.dart';
import '../models/practice_result.dart';
import '../models/typing_state.dart';
import '../models/typing_unit.dart';
import '../services/audio_service.dart';
import '../services/practice_feedback.dart';
import '../services/practice_records.dart';
import '../services/exercise_scoring.dart';
import '../services/speech_coordinator.dart';

export '../models/typing_state.dart';

/// Coordinates speech around pure Dart typing state transitions.
class TypingController extends ChangeNotifier {
  TypingController({
    required TypingExercise exercise,
    required this._speech,
    TypingMode mode = TypingMode.simple,
    PracticeRecords? records,
    this.onAttempt,
    this._countdownInterval = const Duration(seconds: 1),
  }) : _manager = TypingSessionManager(exercise, mode: mode),
       _records = records ?? PracticeRecords();

  final AttemptSnapshotSink? onAttempt;
  final TypingSessionManager _manager;
  final SpeechCoordinator _speech;
  final Duration _countdownInterval;
  final PracticeRecords _records;
  PracticeAttempt? _attempt;
  PracticeResult? _practiceResult;
  Future<void>? completionAnnouncement;
  String? lastAttemptId;
  int? _spellingToken;
  Timer? _hintTimer;
  bool _disposed = false;

  PracticeResult? get practiceResult => _practiceResult;
  TypingState get state => _manager.state;
  TypingExercise get exercise => _manager.exercise;
  TypingUnit get sentence => _manager.unit;
  int get sentenceIndex => state.sentenceIndex;
  int get sentenceCount => exercise.units.length;
  int get wordIndex => state.wordIndex;
  int get letterIndex => state.letterIndex;
  List<String> get enteredCharacters => state.enteredCharacters;
  String get enteredText => enteredCharacters.join();
  TypingMode get mode => state.mode;
  int? get countdown => state.countdown;
  ExercisePhase get phase => state.phase;
  bool _current(int token) => !_disposed && _speech.isCurrent(token);

  Future<void> initialize() async {
    final token = _speech.begin();
    try {
      await _speech.audio.setActivityAssets([
        ...AudioCues.speechAssets,
        ...exercise.audioAssets,
        if (exercise.isWordDrill || exercise.type == ActivityType.homework)
          ...PracticeFeedback.audioAssets,
      ]);
      if (!_current(token)) return;
      _manager.ready();
      _attempt?.interrupt();
      _attempt = null;
      _practiceResult = null;
      notifyListeners();
      await _speech.say(token, AudioCues.welcome);
    } catch (_) {
      _fail(token);
    }
  }

  void start() {
    if (phase == ExercisePhase.error) {
      unawaited(initialize());
      return;
    }
    if (!_manager.restart()) return;
    _attempt?.interrupt();
    _practiceResult = null;
    final attempt = PracticeAttempt(
      mode: mode,
      activityId: exercise.id,
      activityType: exercise.type.name,
      onSnapshot: onAttempt,
    );
    _attempt = attempt;
    lastAttemptId = attempt.id;
    completionAnnouncement = null;
    attempt
      ..setAcceptingInput(exercise.isWordDrill)
      ..publish();
    notifyListeners();
    unawaited(_beginUnit(_speech.begin()));
  }

  Future<void> _beginUnit(
    int token, {
    bool celebrate = false,
    bool announceMode = false,
  }) async {
    try {
      if (announceMode && !await _speech.say(token, _modeAudio)) return;
      if (celebrate &&
          !await _speech.celebrate(token, sentence: !exercise.isWordDrill)) {
        return;
      }
      if (!exercise.isWordDrill) {
        if (!await _speech.say(token, sentence.audioAsset)) return;
        for (var number = 3; number >= 1; number--) {
          _manager.countDown(number);
          notifyListeners();
          final clock = Stopwatch()..start();
          if (!await _speech.say(token, AudioCues.count(number))) return;
          if (!await _speech.wait(token, _countdownInterval - clock.elapsed)) {
            return;
          }
        }
        _manager.beginTyping();
        _attempt?.setAcceptingInput(true);
        notifyListeners();
      }
      await _speakWord(token);
    } catch (_) {
      _fail(token);
    }
  }

  Future<void> _speakWord(int token) async {
    final word = sentence.words[wordIndex];
    final letters = word.split('').map(AudioCues.letter);
    _spellingToken = token;
    try {
      if (sentence.promptStyle == PromptStyle.letters) {
        await _speech.sequence(
          token,
          letters,
          gap: const Duration(milliseconds: 250),
        );
      } else {
        if (!await _speech.say(token, sentence.wordAudioAsset(wordIndex))) {
          return;
        }
        if (!await _speech.wait(token, const Duration(seconds: 1))) return;
        await _speech.sequence(
          token,
          letters,
          gap: const Duration(milliseconds: 250),
        );
      }
    } finally {
      if (_spellingToken == token) _spellingToken = null;
      if (_current(token)) _scheduleHint();
    }
  }

  void _cancelHint() {
    _hintTimer?.cancel();
    _hintTimer = null;
  }

  void _scheduleHint() {
    _cancelHint();
    if (_disposed ||
        phase != ExercisePhase.typing ||
        mode != TypingMode.simple) {
      return;
    }
    _hintTimer = Timer(const Duration(milliseconds: 2000), () {
      _hintTimer = null;
      if (_disposed ||
          phase != ExercisePhase.typing ||
          mode != TypingMode.simple) {
        return;
      }
      final token = _speech.begin();
      final letter = sentence.words[wordIndex][letterIndex];
      unawaited(
        _speech.say(token, AudioCues.letter(letter)).catchError((Object _) {
          _fail(token);
          return false;
        }),
      );
    });
  }

  void typeCharacter(String character) {
    cancelSpelling();
    if (phase != ExercisePhase.typing || character.trim().isEmpty) return;
    _cancelHint();
    final target = sentence.words[wordIndex][letterIndex];
    final position = '$sentenceIndex:$wordIndex:$letterIndex';
    final aligned = enteredCharacters.length == letterIndex;
    final result = _manager.typeCharacter(character);
    if (result == TypingResult.ignored) return;
    if (result == TypingResult.incorrect) _attempt?.recordError();
    if (aligned) {
      _attempt?.recordTarget(
        position,
        target,
        correct: result != TypingResult.incorrect,
      );
    }
    final attempt = _attempt;
    if (result == TypingResult.completed && attempt != null) {
      final result = attempt.finish();
      if (exercise.type == ActivityType.homework) {
        final score = ExerciseScoring(baselineSeconds: exercise.baselineSeconds)
            .score(seconds: result.seconds, mistakes: result.errors);
        _practiceResult = PracticeResult(
          seconds: result.seconds,
          errors: result.errors,
          mode: result.mode,
          changedMode: result.changedMode,
          score: score,
        );
      } else if (exercise.isWordDrill) {
        _practiceResult = _records.finish(
          exercise.id,
          result,
          scoring: ExerciseScoring(baselineSeconds: exercise.baselineSeconds),
        );
      }
      attempt.publish(status: 'completed', score: _practiceResult?.score);
      _attempt = null;
    } else {
      if (result == TypingResult.unitAdvanced && !exercise.isWordDrill) {
        _attempt?.setAcceptingInput(false);
      }
      _attempt?.publish();
    }
    try {
      _speech.audio.feedback(correct: result != TypingResult.incorrect);
      notifyListeners();
      switch (result) {
        case TypingResult.wordAdvanced:
          unawaited(_rewardThenPrompt(_speech.begin()));
        case TypingResult.unitAdvanced:
          unawaited(_beginUnit(_speech.begin(), celebrate: true));
        case TypingResult.completed:
          completionAnnouncement = _finish(_speech.begin());
          unawaited(completionAnnouncement);
        default:
          _scheduleHint();
          break;
      }
    } catch (_) {
      _fail(_speech.begin());
    }
  }

  Future<void> _rewardThenPrompt(int token) async {
    try {
      if (await _speech.celebrate(token, sentence: false)) {
        await _speakWord(token);
      }
    } catch (_) {
      _fail(token);
    }
  }

  Future<void> _finish(int token) async {
    try {
      if (await _speech.celebrate(token, sentence: !exercise.isWordDrill)) {
        await _speech.sequence(token, [
          if (_practiceResult case final result?)
            ...PracticeFeedback.speech(result),
          AudioCues.complete,
        ]);
      }
    } catch (_) {
      _fail(token);
    }
  }

  void backspace() {
    cancelSpelling();
    _manager.backspace();
    notifyListeners();
  }

  String get _modeAudio =>
      mode == TypingMode.simple ? AudioCues.modeSimple : AudioCues.modeAdvanced;
  void toggleMode() {
    if (_disposed ||
        phase == ExercisePhase.loading ||
        phase == ExercisePhase.error) {
      return;
    }
    cancelSpelling();
    _cancelHint();
    _manager.toggleMode();
    _attempt?.recordModeChange();
    _attempt?.publish();
    notifyListeners();
    if (phase == ExercisePhase.reading) {
      unawaited(_beginUnit(_speech.begin(), announceMode: true));
    } else {
      _say([_modeAudio]);
    }
  }

  void repeatWord() {
    if (phase != ExercisePhase.typing) return;
    cancelSpelling();
    _cancelHint();
    final token = _speech.begin();
    unawaited(_speakWord(token).catchError((Object _) => _fail(token)));
  }

  void spellEnteredLetters() {
    cancelSpelling();
    if (phase != ExercisePhase.typing || enteredCharacters.isEmpty) return;
    _cancelHint();
    final token = _speech.begin();
    _spellingToken = token;
    unawaited(_spell(token, enteredCharacters));
  }

  Future<void> _spell(int token, List<String> characters) async {
    try {
      await _speech.sequence(
        token,
        characters.map(AudioCues.letter),
        gap: const Duration(milliseconds: 250),
      );
    } catch (_) {
      _fail(token);
    } finally {
      if (_spellingToken == token) _spellingToken = null;
      if (_current(token)) _scheduleHint();
    }
  }

  void cancelSpelling() {
    final token = _spellingToken;
    _spellingToken = null;
    if (token != null && _speech.isCurrent(token)) _speech.begin();
  }

  void pause() {
    if (!_manager.pause()) return;
    _cancelHint();
    _attempt?.setAcceptingInput(false);
    _attempt?.publish();
    _spellingToken = null;
    _speech.begin();
    notifyListeners();
  }

  void togglePause() {
    if (phase != ExercisePhase.paused) {
      pause();
      return;
    }
    if (!_manager.resume()) return;
    _attempt?.setAcceptingInput(phase == ExercisePhase.typing);
    _attempt?.publish();
    notifyListeners();
    if (phase == ExercisePhase.typing) {
      repeatWord();
    } else {
      unawaited(_beginUnit(_speech.begin()));
    }
  }

  void _say(Iterable<String> assets) {
    cancelSpelling();
    final token = _speech.begin();
    unawaited(
      _speech
          .sequence(token, assets)
          .then((_) {
            if (_current(token)) _scheduleHint();
          })
          .catchError((Object _) => _fail(token)),
    );
  }

  void _fail(int token) {
    if (!_current(token)) return;
    _spellingToken = null;
    _cancelHint();
    _speech.begin();
    _manager.fail();
    _attempt?.setAcceptingInput(false);
    notifyListeners();
  }

  @override
  void dispose() {
    _attempt?.interrupt();
    _cancelHint();
    _disposed = true;
    _speech.begin();
    super.dispose();
  }
}
