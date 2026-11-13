import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import '../models/practice_result.dart';

class PracticeRecords {
  PracticeRecords({this._read, this._write});

  final Future<String?> Function()? _read;
  final Future<void> Function(String)? _write;
  final Map<String, ({int seconds, int errors, int? highScore})> _records = {};
  Future<void>? _loading;
  Future<void> _pendingWrite = Future.value();
  bool _loaded = false;

  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final saved = await _read?.call();
      if (saved != null) {
        final entries = jsonDecode(saved) as Map<String, dynamic>;
        for (final MapEntry(:key, :value) in entries.entries) {
          if (value is List && (value.length == 2 || value.length == 3)) {
            final seconds = value[0];
            final errors = value[1];
            final highScore = value.length == 3 ? value[2] : null;
            if (seconds is int &&
                seconds >= 0 &&
                errors is int &&
                errors >= 0 &&
                (highScore == null || (highScore is int && highScore >= 0))) {
              _records[key] = (
                seconds: seconds,
                errors: errors,
                highScore: highScore as int?,
              );
            }
          }
        }
      }
      _loaded = true;
    } catch (error) {
      developer.log('Could not load practice records', error: error);
    }
  }

  PracticeResult finish(String exerciseId, PracticeResult attempt) {
    if (attempt.changedMode) return attempt;

    final mode = attempt.mode;
    final key = mode == null
        ? 'letters:$exerciseId'
        : 'words:$exerciseId:${mode.name}';
    final score =
        (100 * 180 / max(1, attempt.seconds) * pow(0.95, attempt.errors - 10))
            .round();
    final previous = _records[key];
    final highScore = max(score, previous?.highScore ?? score);
    final bestTime = previous != null && attempt.seconds < previous.seconds;
    final fewestErrors = previous != null && attempt.errors < previous.errors;
    if (previous == null ||
        bestTime ||
        fewestErrors ||
        previous.highScore != highScore) {
      _records[key] = previous == null
          ? (
              seconds: attempt.seconds,
              errors: attempt.errors,
              highScore: highScore,
            )
          : (
              seconds: min(previous.seconds, attempt.seconds),
              errors: min(previous.errors, attempt.errors),
              highScore: highScore,
            );
      _persist();
    }

    return PracticeResult(
      seconds: attempt.seconds,
      errors: attempt.errors,
      mode: mode,
      bestTime: bestTime,
      fewestErrors: fewestErrors,
      score: score,
      highScore: highScore,
    );
  }

  void _persist() {
    final write = _write;
    if (!_loaded || write == null) return;
    final snapshot = jsonEncode({
      for (final MapEntry(:key, value: (:seconds, :errors, :highScore))
          in _records.entries)
        key: [seconds, errors, highScore],
    });
    _pendingWrite = _pendingWrite.then((_) async {
      try {
        await write(snapshot);
      } catch (error) {
        developer.log('Could not save practice records', error: error);
      }
    });
  }
}
