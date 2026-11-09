/// Exercise content and audio references, independent of Flutter and playback.
class Sentence {
  Sentence({required this.id, required this.text})
    : words = List.unmodifiable(text.split(' '));

  final String id;
  final String text;
  final List<String> words;

  String get audioAsset => 'assets/audio/${id}_sentence.wav';
  String wordAudioAsset(int index) => 'assets/audio/${id}_word_$index.wav';

  Iterable<String> get audioAssets sync* {
    yield audioAsset;
    for (var index = 0; index < words.length; index++) {
      yield wordAudioAsset(index);
    }
  }
}

final sampleSentences = List<Sentence>.unmodifiable([
  Sentence(id: '01', text: 'Anna almát tett ide'),
  Sentence(id: '02', text: 'Ősszel sűrű köd száll'),
  Sentence(id: '03', text: 'A fiú hűs vizet kér'),
  Sentence(id: '04', text: 'Gyönyörű pillangó ül kint'),
  Sentence(id: '05', text: 'Ízletes meggyet szedünk ma'),
]);
