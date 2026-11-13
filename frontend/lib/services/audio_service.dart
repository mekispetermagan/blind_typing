/// The controller's plain Dart boundary to the audio system.
abstract interface class AudioService {
  Future<void> initialize(Iterable<String> speechAssets);

  /// Replaces activity-specific sources, keeping shared sources.
  Future<void> setActivityAssets(Iterable<String> speechAssets);

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
  static const menuWelcome = 'assets/audio/menu_welcome.wav';
  static const teachingWelcome = 'assets/audio/teaching_welcome.wav';
  static const wrongKeyPrefix = 'assets/audio/wrong_key_prefix.wav';
  static const wrongKeySuffix = 'assets/audio/wrong_key_suffix.wav';
  static const contentError = 'assets/audio/content_error.wav';
  static const welcome = 'assets/audio/welcome.wav';
  static const paused = 'assets/audio/paused.wav';
  static const complete = 'assets/audio/complete.wav';
  static const modeSimple = 'assets/audio/mode_simple.wav';
  static const modeAdvanced = 'assets/audio/mode_advanced.wav';
  static const unknownCharacter = 'assets/audio/unknown_character.wav';
  static const good = 'assets/audio/good.wav';
  static const bad = 'assets/audio/bad.wav';
  static const wordComplete = 'assets/audio/correct.mp3';
  static const sentenceComplete = 'assets/audio/fanfare.mp3';
  static const alphabet = 'aábcdeéfghiíjklmnoóöőpqrstuúüűvwxyz';
  static String count(int number) => 'assets/audio/count_$number.wav';
  static String letter(String character) {
    final digit = int.tryParse(character);
    if (digit != null && character.length == 1) {
      if (digit >= 1 && digit <= 3) return count(digit);
      return 'assets/audio/result_number_$digit.wav';
    }
    final lower = character.toLowerCase();
    if (lower.length != 1 || !alphabet.contains(lower)) return unknownCharacter;
    return 'assets/audio/letter_${lower.runes.single.toRadixString(16).padLeft(4, '0')}.wav';
  }

  static Iterable<String> get speechAssets => [
    menuWelcome,
    teachingWelcome,
    wrongKeyPrefix,
    wrongKeySuffix,
    contentError,
    welcome,
    paused,
    complete,
    modeSimple,
    modeAdvanced,
    unknownCharacter,
    for (var number = 1; number <= 3; number++) count(number),
    for (final number in [0, 4, 5, 6, 7, 8, 9])
      'assets/audio/result_number_$number.wav',
    for (final character in alphabet.split('')) letter(character),
  ];
}
