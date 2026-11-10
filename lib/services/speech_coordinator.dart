import 'audio_service.dart';

/// A single cancellation boundary shared by navigation and activity speech.
class SpeechCoordinator {
  SpeechCoordinator(this.audio);
  final AudioService audio;
  int _generation = 0;

  int begin() {
    ++_generation;
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

  Future<bool> wait(int token, Duration duration) async {
    if (!isCurrent(token)) return false;
    if (duration > Duration.zero) await Future<void>.delayed(duration);
    return isCurrent(token);
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
