import 'typing_state.dart';

class PracticeResult {
  const PracticeResult({
    required this.seconds,
    required this.errors,
    this.mode,
    this.changedMode = false,
    this.bestTime = false,
    this.fewestErrors = false,
  });

  final int seconds;
  final int errors;
  final TypingMode? mode;
  final bool changedMode;
  final bool bestTime;
  final bool fewestErrors;
}
