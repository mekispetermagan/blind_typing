import 'dart:convert';

import '../models/exercise.dart';
import '../models/menu.dart';
import '../services/content_repository.dart';
import 'backend.dart';

class HttpContentRepository implements ContentRepository {
  Future<Map<String, dynamic>> _read(String path) async {
    final response = await backendGet(path);
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw StateError('Backend returned ${response.statusCode}');
    }
    return jsonDecode(await response.transform(utf8.decoder).join())
        as Map<String, dynamic>;
  }

  @override
  Future<MenuCatalog> loadMenu() async =>
      MenuCatalog.fromJson(await _read('/api/menu'));

  @override
  Future<ExerciseDefinition> loadExercise(ActivityReference reference) async {
    final match = RegExp(r'^data/(lessons|practice)/([a-zA-Z0-9_]+\.json)$')
        .firstMatch(reference.content);
    if (match == null) throw const FormatException('Invalid activity path');
    final exercise = ExerciseDefinition.fromJson(
      await _read('/api/activities/${match[1]}/${match[2]}'),
    );
    if (exercise.type != reference.type) {
      throw const FormatException('Activity type mismatch');
    }
    return exercise;
  }
}
