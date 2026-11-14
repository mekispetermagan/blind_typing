import 'dart:async';
import 'dart:math';

import '../models/practice_result.dart';
import '../models/exercise_phase.dart';

typedef AttemptSnapshotSink = void Function(Map<String, dynamic> snapshot);

/// Measures active input time and the first try at each target position.
class PracticeAttempt {
  PracticeAttempt({
    this.mode,
    Stopwatch? timer,
    this.activityId,
    this.activityType,
    this.onSnapshot,
  }) : _timer = timer ?? Stopwatch(),
       startedAt = DateTime.now().toUtc(),
       id = _newId();

  static String _newId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  final TypingMode? mode;
  final Stopwatch _timer;
  final String? activityId;
  final String? activityType;
  final AttemptSnapshotSink? onSnapshot;
  final DateTime startedAt;
  final String id;
  final Set<String> _positions = {};
  final Map<String, ({int correct, int incorrect})> _keys = {};
  int _errors = 0;
  int _revision = 0;
  bool _changedMode = false;
  bool _finished = false;
  Timer? _heartbeat;

  void setAcceptingInput(bool acceptsInput) {
    if (acceptsInput) {
      _timer.start();
    } else {
      _timer.stop();
    }
  }

  void recordError() => _errors++;
  void recordModeChange() => _changedMode = true;

  void recordTarget(String position, String key, {required bool correct}) {
    if (!_positions.add(position)) return;
    key = key.toLowerCase();
    final previous = _keys[key] ?? (correct: 0, incorrect: 0);
    _keys[key] = (
      correct: previous.correct + (correct ? 1 : 0),
      incorrect: previous.incorrect + (correct ? 0 : 1),
    );
  }

  void publish({String status = 'in_progress', int? score}) {
    if (onSnapshot == null ||
        activityId == null ||
        activityType == null ||
        _finished) {
      return;
    }
    final ended = status == 'in_progress' ? null : DateTime.now().toUtc();
    if (ended == null) {
      _heartbeat ??= Timer.periodic(
        const Duration(seconds: 10),
        (_) => publish(),
      );
    } else {
      _heartbeat?.cancel();
      _heartbeat = null;
    }
    onSnapshot!({
      'id': id,
      'revision': _revision++,
      'activity_id': activityId,
      'activity_type': activityType,
      'started_at': startedAt.toIso8601String(),
      'sampled_at': DateTime.now().toUtc().toIso8601String(),
      'ended_at': ended?.toIso8601String(),
      'status': status,
      'active_duration_ms': _timer.elapsed.inMilliseconds,
      'mistake_count': _errors,
      'mode': mode?.name,
      'mode_changed': _changedMode,
      'score': score,
      'keys': {
        for (final entry in _keys.entries)
          entry.key: {
            'first_try_correct_count': entry.value.correct,
            'first_try_incorrect_count': entry.value.incorrect,
          },
      },
    });
    if (ended != null) _finished = true;
  }

  void interrupt() {
    _timer.stop();
    publish(status: 'interrupted');
  }

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
