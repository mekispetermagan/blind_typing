import 'dart:async';

import 'package:flutter/foundation.dart';

import '../managers/typing_session_manager.dart';
import '../models/exercise.dart';
import '../models/typing_state.dart';
import '../models/typing_unit.dart';
import '../services/audio_service.dart';
import '../services/speech_coordinator.dart';

export '../models/typing_state.dart';

/// Coordinates speech around pure Dart typing state transitions.
class TypingController extends ChangeNotifier {
  TypingController({
    required TypingExercise exercise,
    required this._speech,
    TypingMode mode = TypingMode.simple,
    this._countdownInterval = const Duration(seconds: 1),
  }) : _manager = TypingSessionManager(exercise, mode: mode);

  final TypingSessionManager _manager;
  final SpeechCoordinator _speech;
  final Duration _countdownInterval;
  int? _spellingToken;
  bool _disposed = false;

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
      await _speech.audio.initialize([
        ...AudioCues.speechAssets,
        ...exercise.audioAssets,
      ]);
      if (!_current(token)) return;
      _manager.ready();
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
        notifyListeners();
      }
      await _speakWord(token);
    } catch (_) {
      _fail(token);
    }
  }

  Future<void> _speakWord(int token) => _speech.sequence(
    token,
    sentence.promptStyle == PromptStyle.letters
        ? sentence.words[wordIndex].split('').map(AudioCues.letter)
        : [sentence.wordAudioAsset(wordIndex)],
    gap: const Duration(milliseconds: 250),
  );

  void typeCharacter(String character) {
    cancelSpelling();
    final result = _manager.typeCharacter(character);
    if (result == TypingResult.ignored) return;
    try {
      _speech.audio.feedback(correct: result != TypingResult.incorrect);
      notifyListeners();
      switch (result) {
        case TypingResult.wordAdvanced:
          unawaited(_rewardThenPrompt(_speech.begin()));
        case TypingResult.unitAdvanced:
          unawaited(_beginUnit(_speech.begin(), celebrate: true));
        case TypingResult.completed:
          unawaited(_finish(_speech.begin()));
        default:
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
        await _speech.say(token, AudioCues.complete);
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
    _manager.toggleMode();
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
    final token = _speech.begin();
    unawaited(_speakWord(token).catchError((Object _) => _fail(token)));
  }

  void spellEnteredLetters() {
    cancelSpelling();
    if (phase != ExercisePhase.typing || enteredCharacters.isEmpty) return;
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
    }
  }

  void cancelSpelling() {
    final token = _spellingToken;
    _spellingToken = null;
    if (token != null && _speech.isCurrent(token)) _speech.begin();
  }

  void pause() {
    if (!_manager.pause()) return;
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
      _speech.sequence(token, assets).catchError((Object _) => _fail(token)),
    );
  }

  void _fail(int token) {
    if (!_current(token)) return;
    _spellingToken = null;
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
