import 'typing_state.dart';

class PracticeResult {
  const PracticeResult({
    required this.seconds,
    required this.errors,
    this.mode,
    this.changedMode = false,
    this.bestTime = false,
    this.fewestErrors = false,
    this.score,
    this.highScore,
  });

  final int seconds;
  final int errors;
  final TypingMode? mode;
  final bool changedMode;
  final bool bestTime;
  final bool fewestErrors;
  final int? score;
  final int? highScore;
}
