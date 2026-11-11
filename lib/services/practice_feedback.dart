import '../models/practice_result.dart';
import '../models/typing_state.dart';
import 'audio_service.dart';

class PracticeFeedback {
  static const _magnitudes = {
    1000000000: 'billion',
    1000000: 'million',
    1000: 'thousand',
    100: 'hundred',
  };
  static const _bestTime = 'Ez eddig a legjobb időd.';
  static const _fewestErrors = 'Ez eddig a legkevesebb hibád.';
  static const _mixedMode = 'A feladat közben módot váltottál.';

  static String _asset(String name) => 'assets/audio/result_$name.wav';

  static Iterable<String> get audioAssets => [
    for (final cue in [
      'time',
      'minute',
      'second',
      'errors',
      'best_time',
      'fewest_errors',
      'mixed_mode',
      ..._magnitudes.values,
    ])
      _asset(cue),
    for (var number = 0; number < 100; number++) ...[
      if (number < 1 || number > 3) _numberAsset(number),
      if (number % 10 == 2) _numberAsset(number, beforeUnit: true),
    ],
  ];

  static String describe(PracticeResult result) {
    final minutes = result.seconds ~/ 60;
    final seconds = result.seconds % 60;
    return [
      if (result.changedMode)
        _mixedMode
      else if (result.mode case final mode?)
        mode == TypingMode.simple ? 'Egyszerű mód.' : 'Haladó mód.',
      'Az időd ${minutes > 0 ? '$minutes perc ' : ''}$seconds másodperc.',
      'A hibás leütések száma ${result.errors}.',
      if (result.bestTime) _bestTime,
      if (result.fewestErrors) _fewestErrors,
    ].join(' ');
  }

  static Iterable<String> speech(PracticeResult result) sync* {
    if (result.changedMode) {
      yield _asset('mixed_mode');
    } else if (result.mode case final mode?) {
      yield mode == TypingMode.simple
          ? AudioCues.modeSimple
          : AudioCues.modeAdvanced;
    }
    yield _asset('time');
    final minutes = result.seconds ~/ 60;
    if (minutes > 0) {
      yield* _number(minutes, beforeUnit: true);
      yield _asset('minute');
    }
    yield* _number(result.seconds % 60, beforeUnit: true);
    yield _asset('second');
    yield _asset('errors');
    yield* _number(result.errors);
    if (result.bestTime) yield _asset('best_time');
    if (result.fewestErrors) yield _asset('fewest_errors');
  }

  static String _numberAsset(int number, {bool beforeUnit = false}) {
    if (beforeUnit && number % 10 == 2) {
      return _asset('number_${number}_before_unit');
    }
    if (number >= 1 && number <= 3) return AudioCues.count(number);
    return _asset('number_$number');
  }

  static Iterable<String> _number(int number, {bool beforeUnit = false}) sync* {
    for (final MapEntry(key: magnitude, :value) in _magnitudes.entries) {
      if (number < magnitude) continue;
      final count = number ~/ magnitude;
      if (count > 1 || magnitude >= 1000000) {
        yield* _number(count, beforeUnit: true);
      }
      yield _asset(value);
      final rest = number % magnitude;
      if (rest > 0) yield* _number(rest, beforeUnit: beforeUnit);
      return;
    }
    yield _numberAsset(number, beforeUnit: beforeUnit);
  }
}
