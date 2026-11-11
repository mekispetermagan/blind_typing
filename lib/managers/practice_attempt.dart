import '../models/practice_result.dart';
import '../models/typing_state.dart';

/// Measures only the parts of an attempt where the exercise accepts input.
class PracticeAttempt {
  PracticeAttempt({this.mode, Stopwatch? timer})
    : _timer = timer ?? Stopwatch();

  final TypingMode? mode;
  final Stopwatch _timer;
  int _errors = 0;
  bool _changedMode = false;

  void setAcceptingInput(bool acceptsInput) {
    if (acceptsInput) {
      _timer.start();
    } else {
      _timer.stop();
    }
  }

  void recordError() => _errors++;
  void recordModeChange() => _changedMode = true;

  PracticeResult finish() {
    _timer.stop();
    return PracticeResult(
      seconds: _timer.elapsed.inSeconds,
      errors: _errors,
      mode: mode,
      changedMode: _changedMode,
    );
  }
}
