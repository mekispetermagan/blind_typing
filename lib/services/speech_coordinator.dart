import 'dart:async';

import 'audio_service.dart';

/// A single cancellation boundary shared by navigation and activity speech.
class SpeechCoordinator {
  SpeechCoordinator(this.audio);
  final AudioService audio;
  int _generation = 0;
  final Map<Timer, Completer<bool>> _pendingWaits = {};

  int begin() {
    ++_generation;
    for (final entry in _pendingWaits.entries) {
      entry.key.cancel();
      entry.value.complete(false);
    }
    _pendingWaits.clear();
    audio.stopSpeech();
    return _generation;
  }

  bool isCurrent(int token) => token == _generation;
  Future<bool> say(int token, String asset) async {
    if (!isCurrent(token)) return false;
    await audio.speak(asset);
    return isCurrent(token);
  }

  Future<bool> celebrate(int token, {required bool sentence}) async {
    if (!isCurrent(token)) return false;
    await audio.celebrate(sentence: sentence);
    return isCurrent(token);
  }

  Future<bool> wait(int token, Duration duration) {
    if (!isCurrent(token)) return Future.value(false);
    if (duration <= Duration.zero) return Future.value(true);
    final completion = Completer<bool>();
    late final Timer timer;
    timer = Timer(duration, () {
      _pendingWaits.remove(timer);
      completion.complete(isCurrent(token));
    });
    _pendingWaits[timer] = completion;
    return completion.future;
  }

  Future<void> sequence(
    int token,
    Iterable<String> assets, {
    Duration gap = Duration.zero,
  }) async {
    final items = assets.toList();
    for (var index = 0; index < items.length; index++) {
      if (!await say(token, items[index])) return;
      if (index + 1 < items.length && !await wait(token, gap)) return;
    }
  }
}
