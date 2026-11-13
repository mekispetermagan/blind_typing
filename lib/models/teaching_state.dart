import 'exercise_phase.dart';

enum TeachingResult { ignored, incorrect, accepted, stepAdvanced, completed }

class TeachingState {
  const TeachingState({
    this.phase = ExercisePhase.loading,
    this.stepIndex = 0,
    this.successes = 0,
    this.lastKey,
    this.lastCorrect,
  });
  final ExercisePhase phase;
  final int stepIndex;
  final int successes;
  final String? lastKey;
  final bool? lastCorrect;

  TeachingState withPhase(ExercisePhase phase) => TeachingState(
    phase: phase,
    stepIndex: stepIndex,
    successes: successes,
    lastKey: lastKey,
    lastCorrect: lastCorrect,
  );
}
