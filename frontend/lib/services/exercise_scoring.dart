import 'dart:math';

class ExerciseScoring {
  const ExerciseScoring({
    this.baselineSeconds = 180,
    this.baselineMistakes = 10,
    this.mistakeMultiplier = 0.95,
    this.baselinePoints = 100,
  }) : assert(baselineSeconds > 0),
       assert(baselineMistakes >= 0),
       assert(mistakeMultiplier > 0 && mistakeMultiplier <= 1),
       assert(baselinePoints > 0);

  final int baselineSeconds;
  final int baselineMistakes;
  final double mistakeMultiplier;
  final int baselinePoints;

  int score({required int seconds, required int mistakes}) =>
      (baselinePoints *
              baselineSeconds /
              max(1, seconds) *
              pow(mistakeMultiplier, mistakes - baselineMistakes))
          .round();
}
