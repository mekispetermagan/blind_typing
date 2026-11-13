import '../models/exercise.dart';
import '../models/menu.dart';

abstract interface class ContentRepository {
  Future<MenuCatalog> loadMenu();
  Future<ExerciseDefinition> loadExercise(ActivityReference reference);
}
