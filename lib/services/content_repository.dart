import 'dart:convert';

import 'package:flutter/services.dart';

import '../models/exercise.dart';
import '../models/menu.dart';

abstract interface class ContentRepository {
  Future<MenuCatalog> loadMenu();
  Future<ExerciseDefinition> loadExercise(ActivityReference reference);
}

class AssetContentRepository implements ContentRepository {
  Future<Map<String, dynamic>> _read(String path) async =>
      jsonDecode(await rootBundle.loadString(path)) as Map<String, dynamic>;
  @override
  Future<MenuCatalog> loadMenu() async =>
      MenuCatalog.fromJson(await _read('data/menu.json'));
  @override
  Future<ExerciseDefinition> loadExercise(ActivityReference reference) async {
    final exercise = ExerciseDefinition.fromJson(
      await _read(reference.content),
    );
    if (exercise.type != reference.type) {
      throw const FormatException('Activity type mismatch');
    }
    return exercise;
  }
}
