final _wordPattern = RegExp(r'[A-Za-zÁÉÍÓÖŐÚÜŰáéíóöőúüű]+');

/// Keep source punctuation in content; current typing modes use letter targets.
List<String> typingWords(String text) => List.unmodifiable(
  _wordPattern.allMatches(text).map((match) => match.group(0)!),
);
