import 'dart:convert';
import 'dart:io';

import 'package:blind_typing/models/exercise.dart';
import 'package:blind_typing/models/menu.dart';
import 'package:blind_typing/models/typing_unit.dart';
import 'package:blind_typing/services/content_repository.dart';

Map<String, dynamic> readData(String path) =>
    jsonDecode(File('../backend/$path').readAsStringSync())
        as Map<String, dynamic>;
TypingExercise get sampleExercise => practiceExercise([
  TypingUnit(id: 'test_sentence_01', text: 'Anna almát kér ma'),
  TypingUnit(id: 'test_sentence_02', text: 'Esik az eső'),
  TypingUnit(id: 'test_sentence_03', text: 'A fiú vizet kér'),
  TypingUnit(id: 'test_sentence_04', text: 'Pillangó ül itt'),
  TypingUnit(id: 'test_sentence_05', text: 'Ma süt a nap'),
]);
List<TypingUnit> get sampleSentences => sampleExercise.units;
TypingExercise practiceExercise(List<TypingUnit> units) => TypingExercise(
  id: 'test',
  title: 'Test',
  type: ActivityType.practice,
  units: units,
);
TypingExercise get wordExercise =>
    TypingExercise.fromJson(readData('data/lessons/home_row_words.json'));
LetterExercise get letterExercise =>
    LetterExercise.fromJson(readData('data/lessons/home_row_letters.json'));

class FileContentRepository implements ContentRepository {
  bool failExercise = false;
  MenuCatalog? menuOverride;
  final List<String> loaded = [];
  @override
  Future<MenuCatalog> loadMenu() async =>
      menuOverride ?? MenuCatalog.fromJson(readData('data/menu.json'));
  @override
  Future<ExerciseDefinition> loadExercise(ActivityReference reference) async {
    if (failExercise) throw const FormatException('Test content error');
    loaded.add(reference.content);
    return ExerciseDefinition.fromJson(readData(reference.content));
  }
}
