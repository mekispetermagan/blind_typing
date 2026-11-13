import '../models/exercise.dart';
import '../models/teaching_state.dart';
import '../models/exercise_phase.dart';

class LetterTeachingManager {
  LetterTeachingManager(this.exercise);
  final LetterExercise exercise;
  TeachingState _state = const TeachingState();
  TeachingState get state => _state;
  LetterStep get step => exercise.steps[_state.stepIndex];
  void ready() => _state = _state.withPhase(ExercisePhase.ready);
  void fail() => _state = _state.withPhase(ExercisePhase.error);
  bool restart() {
    if (![
      ExercisePhase.ready,
      ExercisePhase.complete,
      ExercisePhase.paused,
    ].contains(_state.phase)) {
      return false;
    }
    _state = const TeachingState(phase: ExercisePhase.typing);
    return true;
  }

  TeachingResult typeCharacter(String character) {
    if (_state.phase != ExercisePhase.typing || character.trim().isEmpty) {
      return TeachingResult.ignored;
    }
    final correct = character.toLowerCase() == step.key.toLowerCase();
    final successes = _state.successes + (correct ? 1 : 0);
    var phase = _state.phase;
    var index = _state.stepIndex;
    var result = correct ? TeachingResult.accepted : TeachingResult.incorrect;
    if (successes == step.requiredSuccesses) {
      if (index + 1 == exercise.steps.length) {
        phase = ExercisePhase.complete;
        result = TeachingResult.completed;
      } else {
        index++;
        phase = ExercisePhase.reading;
        result = TeachingResult.stepAdvanced;
      }
    }
    _state = TeachingState(
      phase: phase,
      stepIndex: index,
      successes: result == TeachingResult.stepAdvanced ? 0 : successes,
      lastKey: character,
      lastCorrect: correct,
    );
    return result;
  }

  bool pause() {
    if (![ExercisePhase.typing, ExercisePhase.reading].contains(_state.phase)) {
      return false;
    }
    _state = _state.withPhase(ExercisePhase.paused);
    return true;
  }

  void beginStep() => _state = _state.withPhase(ExercisePhase.typing);
  bool resume() {
    if (_state.phase != ExercisePhase.paused) return false;
    beginStep();
    return true;
  }
}
