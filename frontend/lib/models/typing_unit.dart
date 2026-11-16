import '../utils/typing_text.dart';

enum PromptStyle { word, letters }

/// One sentence in practice, or one target in a word drill.
class TypingUnit {
  TypingUnit({
    required this.id,
    required this.text,
    this.promptStyle = PromptStyle.word,
    this.homework = false,
    this.sentenceAudio,
    this.wordAudio,
  }) : words = homework
           ? List.unmodifiable(
               RegExp(
                 r'[\p{L}\p{N}]+',
                 unicode: true,
               ).allMatches(text).map((m) => m.group(0)!),
             )
           : RegExp(r'^[0-9]+$').hasMatch(text)
           ? List.unmodifiable([text])
           : typingWords(text) {
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(id) || words.isEmpty) {
      throw FormatException('Invalid typing unit: $id');
    }
  }

  factory TypingUnit.fromJson(
    Map<String, dynamic> json, {
    bool homework = false,
  }) => TypingUnit(
    id: json['id'] as String,
    text: json['text'] as String,
    homework: homework,
    sentenceAudio: json['sentenceAudio'] as String?,
    wordAudio: (json['wordAudio'] as List?)?.cast<String>(),
    promptStyle: PromptStyle.values.byName(
      json['promptStyle'] as String? ?? 'word',
    ),
  );

  final String id;
  final String text;
  final List<String> words;
  final PromptStyle promptStyle;
  final bool homework;
  final String? sentenceAudio;
  final List<String>? wordAudio;
  String get audioAsset => sentenceAudio ?? 'assets/audio/${id}_sentence.wav';
  String wordAudioAsset(int index) =>
      wordAudio?[index] ?? 'assets/audio/${id}_word_$index.wav';

  Iterable<String> audioAssets({required bool readSentence}) sync* {
    if (readSentence) yield audioAsset;
    if (promptStyle == PromptStyle.word) {
      for (var index = 0; index < words.length; index++) {
        yield wordAudioAsset(index);
      }
    }
  }
}
