import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/sentence.dart';
import '../services/audio_service.dart';

enum ExercisePhase {
  loading,
  ready,
  reading,
  countdown,
  typing,
  paused,
  complete,
  error,
}

enum TypingMode { simple, advanced }

class TypingController extends ChangeNotifier {
  TypingController({
    required List<Sentence> sentences,
    required this._audio,
    this._countdownInterval = const Duration(seconds: 1),
  }) : assert(sentences.isNotEmpty),
       _sentences = List.unmodifiable(sentences);

  final List<Sentence> _sentences;
  final AudioService _audio;
  final Duration _countdownInterval;
  ExercisePhase _phase = ExercisePhase.loading;
  ExercisePhase? _pausedPhase;
  int _sentenceIndex = 0;
  int _wordIndex = 0;
  int _letterIndex = 0;
  final List<String> _enteredCharacters = [];
  TypingMode _mode = TypingMode.simple;
  int? _countdown;
  int _generation = 0;
  int? _spellingGeneration;
  bool _disposed = false;

  Sentence get sentence => _sentences[_sentenceIndex];
  int get sentenceIndex => _sentenceIndex;
  int get sentenceCount => _sentences.length;
  int get wordIndex => _wordIndex;
  int get letterIndex => _letterIndex;
  List<String> get enteredCharacters => List.unmodifiable(_enteredCharacters);
  String get enteredText => _enteredCharacters.join();
  TypingMode get mode => _mode;
  int? get countdown => _countdown;
  ExercisePhase get phase => _phase;
  bool _isCurrent(int generation) => !_disposed && generation == _generation;

  Future<void> initialize() async {
    final generation = ++_generation;
    _phase = ExercisePhase.loading;
    notifyListeners();
    try {
      await _audio.initialize([
        ...AudioCues.speechAssets,
        for (final sentence in _sentences) ...sentence.audioAssets,
      ]);
      if (!_isCurrent(generation)) return;
      _phase = ExercisePhase.ready;
      notifyListeners();
      await _audio.speak(AudioCues.welcome);
    } catch (_) {
      _fail(generation);
    }
  }

  void start() {
    if (_phase == ExercisePhase.error) {
      unawaited(initialize());
      return;
    }
    if (_phase != ExercisePhase.ready && _phase != ExercisePhase.complete) {
      return;
    }
    _sentenceIndex = 0;
    _wordIndex = 0;
    _letterIndex = 0;
    _enteredCharacters.clear();
    unawaited(_beginSentence(++_generation));
  }

  Future<void> _beginSentence(
    int generation, {
    bool celebrate = false,
    bool announceMode = false,
  }) async {
    try {
      _phase = ExercisePhase.reading;
      _countdown = null;
      notifyListeners();
      if (announceMode) {
        await _audio.speak(_modeAudio);
        if (!_isCurrent(generation)) return;
      }
      if (celebrate) {
        await _audio.celebrate(sentence: true);
        if (!_isCurrent(generation)) return;
      }
      await _audio.speak(sentence.audioAsset);
      if (!_isCurrent(generation)) return;
      _phase = ExercisePhase.countdown;
      for (var number = 3; number >= 1; number--) {
        _countdown = number;
        notifyListeners();
        final clock = Stopwatch()..start();
        await _audio.speak(AudioCues.count(number));
        if (!_isCurrent(generation)) return;
        final remaining = _countdownInterval - clock.elapsed;
        if (remaining > Duration.zero) await Future<void>.delayed(remaining);
        if (!_isCurrent(generation)) return;
      }
      _countdown = null;
      _phase = ExercisePhase.typing;
      notifyListeners();
      await _audio.speak(sentence.wordAudioAsset(_wordIndex));
    } catch (_) {
      _fail(generation);
    }
  }

  void typeCharacter(String character) {
    cancelSpelling();
    if (_phase != ExercisePhase.typing || character.trim().isEmpty) return;
    final word = sentence.words[_wordIndex];
    final correct =
        _enteredCharacters.length == _letterIndex &&
        character.toLowerCase() == word[_letterIndex].toLowerCase();
    try {
      _audio.feedback(correct: correct);
      if (!correct && _mode == TypingMode.simple) return;
      _enteredCharacters.add(character);
      if (!correct) {
        notifyListeners();
        return;
      }
      _letterIndex++;
      if (_letterIndex < word.length) {
        notifyListeners();
        return;
      }
      if (_wordIndex + 1 < sentence.words.length) {
        _wordIndex++;
        _letterIndex = 0;
        _enteredCharacters.clear();
        notifyListeners();
        unawaited(_celebrateThenSpeak(sentence.wordAudioAsset(_wordIndex)));
      } else if (_sentenceIndex + 1 < _sentences.length) {
        _sentenceIndex++;
        _wordIndex = 0;
        _letterIndex = 0;
        _enteredCharacters.clear();
        unawaited(_beginSentence(++_generation, celebrate: true));
      } else {
        _phase = ExercisePhase.complete;
        notifyListeners();
        unawaited(_celebrateThenSpeak(AudioCues.complete, sentence: true));
      }
    } catch (_) {
      _fail(_generation);
    }
  }

  void backspace() {
    cancelSpelling();
    if (_phase != ExercisePhase.typing ||
        _mode != TypingMode.advanced ||
        _enteredCharacters.isEmpty) {
      return;
    }
    _enteredCharacters.removeLast();
    if (_letterIndex > _enteredCharacters.length) {
      _letterIndex = _enteredCharacters.length;
    }
    notifyListeners();
  }

  String get _modeAudio => _mode == TypingMode.simple
      ? AudioCues.modeSimple
      : AudioCues.modeAdvanced;

  void toggleMode() {
    if (_disposed ||
        _phase == ExercisePhase.loading ||
        _phase == ExercisePhase.error) {
      return;
    }
    cancelSpelling();
    _mode = _mode == TypingMode.simple
        ? TypingMode.advanced
        : TypingMode.simple;
    if (_mode == TypingMode.simple) {
      _enteredCharacters.removeRange(_letterIndex, _enteredCharacters.length);
    }
    notifyListeners();
    if (_phase == ExercisePhase.reading || _phase == ExercisePhase.countdown) {
      // Changing modes must not leave an interrupted countdown or reading stuck.
      unawaited(_beginSentence(++_generation, announceMode: true));
    } else {
      _speak(_modeAudio);
    }
  }

  Future<void> _celebrateThenSpeak(
    String asset, {
    bool sentence = false,
  }) async {
    final generation = ++_generation;
    try {
      await _audio.celebrate(sentence: sentence);
      if (!_isCurrent(generation)) return;
      await _audio.speak(asset);
    } catch (_) {
      _fail(generation);
    }
  }

  void repeatWord() {
    if (_phase == ExercisePhase.typing) {
      _speak(sentence.wordAudioAsset(_wordIndex));
    }
  }

  void spellEnteredLetters() {
    cancelSpelling();
    if (_phase != ExercisePhase.typing || _enteredCharacters.isEmpty) return;
    final characters = List<String>.of(_enteredCharacters);
    final generation = ++_generation;
    _spellingGeneration = generation;
    unawaited(_spell(characters, generation));
  }

  Future<void> _spell(List<String> characters, int generation) async {
    try {
      for (var index = 0; index < characters.length; index++) {
        if (!_isCurrent(generation)) return;
        await _audio.speak(AudioCues.letter(characters[index]));
        if (!_isCurrent(generation)) return;
        if (index + 1 < characters.length) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
        }
      }
    } catch (_) {
      _fail(generation);
    } finally {
      if (_spellingGeneration == generation) _spellingGeneration = null;
    }
  }

  void cancelSpelling() {
    if (_spellingGeneration == null) return;
    _spellingGeneration = null;
    ++_generation;
    _audio.stopSpeech();
  }

  void togglePause() {
    if (_phase != ExercisePhase.paused) {
      pause();
      return;
    }
    final previous = _pausedPhase;
    _pausedPhase = null;
    final generation = ++_generation;
    if (previous == ExercisePhase.typing) {
      _phase = ExercisePhase.typing;
      notifyListeners();
      _speak(sentence.wordAudioAsset(_wordIndex));
    } else {
      // Restart interrupted instructions with a full countdown.
      unawaited(_beginSentence(generation));
    }
  }

  void pause() {
    if (_phase != ExercisePhase.typing &&
        _phase != ExercisePhase.reading &&
        _phase != ExercisePhase.countdown) {
      return;
    }
    _pausedPhase = _phase;
    _phase = ExercisePhase.paused;
    _countdown = null;
    ++_generation;
    notifyListeners();
    _speak(AudioCues.paused);
  }

  void _speak(String asset) {
    cancelSpelling();
    final generation = ++_generation;
    try {
      unawaited(
        _audio.speak(asset).catchError((Object _) => _fail(generation)),
      );
    } catch (_) {
      _fail(generation);
    }
  }

  void _fail(int generation) {
    if (!_isCurrent(generation)) return;
    _spellingGeneration = null;
    ++_generation;
    _phase = ExercisePhase.error;
    _countdown = null;
    _audio.stopSpeech();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _audio.stopSpeech();
    unawaited(_audio.dispose());
    super.dispose();
  }
}
