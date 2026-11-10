import '../models/exercise.dart';
import '../models/typing_state.dart';
import '../models/typing_unit.dart';

/// All typing rules and progression, independent of UI, clocks, and audio.
class TypingSessionManager {
  TypingSessionManager(this.exercise, {TypingMode mode = TypingMode.simple})
    : _state = TypingState(mode: mode);

  final TypingExercise exercise;
  TypingState _state;
  TypingState get state => _state;
  TypingUnit get unit => exercise.units[_state.sentenceIndex];

  void ready() =>
      _state = _state.copyWith(phase: ExercisePhase.ready, countdown: null);
  void fail() =>
      _state = _state.copyWith(phase: ExercisePhase.error, countdown: null);

  bool restart() {
    if (![
      ExercisePhase.ready,
      ExercisePhase.complete,
      ExercisePhase.paused,
    ].contains(_state.phase)) {
      return false;
    }
    _state = TypingState(
      mode: _state.mode,
      phase: exercise.isWordDrill
          ? ExercisePhase.typing
          : ExercisePhase.reading,
    );
    return true;
  }

  void countDown(int number) => _state = _state.copyWith(
    phase: ExercisePhase.countdown,
    countdown: number,
  );
  void beginTyping() =>
      _state = _state.copyWith(phase: ExercisePhase.typing, countdown: null);

  TypingResult typeCharacter(String character) {
    if (_state.phase != ExercisePhase.typing || character.trim().isEmpty) {
      return TypingResult.ignored;
    }
    final correct =
        _state.enteredCharacters.length == _state.letterIndex &&
        character.toLowerCase() ==
            unit.words[_state.wordIndex][_state.letterIndex].toLowerCase();
    if (!correct && _state.mode == TypingMode.simple) {
      return TypingResult.incorrect;
    }
    _state = _state.copyWith(
      enteredCharacters: [..._state.enteredCharacters, character],
    );
    if (!correct) return TypingResult.incorrect;
    _state = _state.copyWith(letterIndex: _state.letterIndex + 1);
    if (_state.letterIndex < unit.words[_state.wordIndex].length) {
      return TypingResult.accepted;
    }
    if (_state.wordIndex + 1 < unit.words.length) {
      _state = _state.copyWith(
        wordIndex: _state.wordIndex + 1,
        letterIndex: 0,
        enteredCharacters: [],
      );
      return TypingResult.wordAdvanced;
    }
    if (_state.sentenceIndex + 1 < exercise.units.length) {
      _state = _state.copyWith(
        sentenceIndex: _state.sentenceIndex + 1,
        wordIndex: 0,
        letterIndex: 0,
        enteredCharacters: [],
        phase: exercise.isWordDrill
            ? ExercisePhase.typing
            : ExercisePhase.reading,
      );
      return TypingResult.unitAdvanced;
    }
    _state = _state.copyWith(phase: ExercisePhase.complete);
    return TypingResult.completed;
  }

  void backspace() {
    if (_state.phase != ExercisePhase.typing ||
        _state.mode != TypingMode.advanced ||
        _state.enteredCharacters.isEmpty) {
      return;
    }
    final entered = _state.enteredCharacters
        .take(_state.enteredCharacters.length - 1)
        .toList();
    _state = _state.copyWith(
      enteredCharacters: entered,
      letterIndex: _state.letterIndex > entered.length
          ? entered.length
          : _state.letterIndex,
    );
  }

  void toggleMode() {
    final mode = _state.mode == TypingMode.simple
        ? TypingMode.advanced
        : TypingMode.simple;
    final interrupted =
        _state.phase == ExercisePhase.reading ||
        _state.phase == ExercisePhase.countdown;
    _state = _state.copyWith(
      mode: mode,
      enteredCharacters: mode == TypingMode.simple
          ? _state.enteredCharacters.take(_state.letterIndex).toList()
          : null,
      phase: interrupted ? ExercisePhase.reading : null,
      countdown: null,
    );
  }

  bool pause() {
    if (![
      ExercisePhase.typing,
      ExercisePhase.reading,
      ExercisePhase.countdown,
    ].contains(_state.phase)) {
      return false;
    }
    _state = _state.copyWith(
      pausedPhase: _state.phase,
      phase: ExercisePhase.paused,
      countdown: null,
    );
    return true;
  }

  bool resume() {
    if (_state.phase != ExercisePhase.paused) return false;
    _state = _state.copyWith(
      phase: _state.pausedPhase == ExercisePhase.typing
          ? ExercisePhase.typing
          : ExercisePhase.reading,
      pausedPhase: null,
    );
    return true;
  }
}
