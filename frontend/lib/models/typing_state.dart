import 'exercise_phase.dart';
export 'exercise_phase.dart';

enum TypingResult {
  ignored,
  incorrect,
  accepted,
  wordAdvanced,
  unitAdvanced,
  completed,
}

const _unchanged = Object();

class TypingState {
  TypingState({
    this.phase = ExercisePhase.loading,
    this.sentenceIndex = 0,
    this.wordIndex = 0,
    this.letterIndex = 0,
    List<String> enteredCharacters = const [],
    this.mode = TypingMode.simple,
    this.countdown,
    this.pausedPhase,
  }) : enteredCharacters = List.unmodifiable(enteredCharacters);

  final ExercisePhase phase;
  final int sentenceIndex;
  final int wordIndex;
  final int letterIndex;
  final List<String> enteredCharacters;
  final TypingMode mode;
  final int? countdown;
  final ExercisePhase? pausedPhase;

  TypingState copyWith({
    ExercisePhase? phase,
    int? sentenceIndex,
    int? wordIndex,
    int? letterIndex,
    List<String>? enteredCharacters,
    TypingMode? mode,
    Object? countdown = _unchanged,
    Object? pausedPhase = _unchanged,
  }) => TypingState(
    phase: phase ?? this.phase,
    sentenceIndex: sentenceIndex ?? this.sentenceIndex,
    wordIndex: wordIndex ?? this.wordIndex,
    letterIndex: letterIndex ?? this.letterIndex,
    enteredCharacters: enteredCharacters ?? this.enteredCharacters,
    mode: mode ?? this.mode,
    countdown: identical(countdown, _unchanged)
        ? this.countdown
        : countdown as int?,
    pausedPhase: identical(pausedPhase, _unchanged)
        ? this.pausedPhase
        : pausedPhase as ExercisePhase?,
  );
}
