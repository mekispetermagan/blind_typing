import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import '../models/practice_result.dart';

class PracticeRecords {
  PracticeRecords({this._read, this._write});

  final Future<String?> Function()? _read;
  final Future<void> Function(String)? _write;
  final Map<String, ({int seconds, int errors})> _records = {};
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
          if (value case [final int seconds, final int errors]
              when seconds >= 0 && errors >= 0) {
            _records[key] = (seconds: seconds, errors: errors);
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
    final previous = _records[key];
    final bestTime = previous != null && attempt.seconds < previous.seconds;
    final fewestErrors = previous != null && attempt.errors < previous.errors;
    if (previous == null || bestTime || fewestErrors) {
      _records[key] = previous == null
          ? (seconds: attempt.seconds, errors: attempt.errors)
          : (
              seconds: min(previous.seconds, attempt.seconds),
              errors: min(previous.errors, attempt.errors),
            );
      _persist();
    }

    return PracticeResult(
      seconds: attempt.seconds,
      errors: attempt.errors,
      mode: mode,
      bestTime: bestTime,
      fewestErrors: fewestErrors,
    );
  }

  void _persist() {
    final write = _write;
    if (!_loaded || write == null) return;
    final snapshot = jsonEncode({
      for (final MapEntry(:key, value: (:seconds, :errors)) in _records.entries)
        key: [seconds, errors],
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
