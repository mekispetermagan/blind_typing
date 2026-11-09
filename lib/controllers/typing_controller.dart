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
  int? _countdown;
  int _generation = 0;
  bool _disposed = false;

  Sentence get sentence => _sentences[_sentenceIndex];
  int get sentenceIndex => _sentenceIndex;
  int get sentenceCount => _sentences.length;
  int get wordIndex => _wordIndex;
  int get letterIndex => _letterIndex;
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
    unawaited(_beginSentence(++_generation));
  }

  Future<void> _beginSentence(int generation, {bool celebrate = false}) async {
    try {
      _phase = ExercisePhase.reading;
      _countdown = null;
      notifyListeners();
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
    if (_phase != ExercisePhase.typing || character.trim().isEmpty) return;
    final word = sentence.words[_wordIndex];
    final correct = character.toLowerCase() == word[_letterIndex].toLowerCase();
    try {
      _audio.feedback(correct: correct);
      if (!correct) return;
      _letterIndex++;
      if (_letterIndex < word.length) {
        notifyListeners();
        return;
      }
      if (_wordIndex + 1 < sentence.words.length) {
        _wordIndex++;
        _letterIndex = 0;
        notifyListeners();
        unawaited(_celebrateThenSpeak(sentence.wordAudioAsset(_wordIndex)));
      } else if (_sentenceIndex + 1 < _sentences.length) {
        _sentenceIndex++;
        _wordIndex = 0;
        _letterIndex = 0;
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
