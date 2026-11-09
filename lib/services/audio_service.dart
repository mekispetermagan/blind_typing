/// The controller's plain Dart boundary to the audio system.
abstract interface class AudioService {
  Future<void> initialize(Iterable<String> speechAssets);

  /// Replaces current speech. Completes when finished or interrupted.
  Future<void> speak(String asset);
  void stopSpeech();

  /// Plays the word reward, then the sentence reward when applicable.
  /// A new prompt can interrupt the celebration.
  Future<void> celebrate({required bool sentence});

  /// Must not await speech or queue earlier keystrokes.
  void feedback({required bool correct});
  Future<void> dispose();
}

abstract final class AudioCues {
  static const welcome = 'assets/audio/welcome.wav';
  static const paused = 'assets/audio/paused.wav';
  static const complete = 'assets/audio/complete.wav';
  static const good = 'assets/audio/good.wav';
  static const bad = 'assets/audio/bad.wav';
  static const wordComplete = 'assets/audio/correct.mp3';
  static const sentenceComplete = 'assets/audio/fanfare.mp3';
  static String count(int number) => 'assets/audio/count_$number.wav';

  static Iterable<String> get speechAssets => [
    welcome,
    paused,
    complete,
    for (var number = 1; number <= 3; number++) count(number),
  ];
}
