import 'typing_unit.dart';

enum ActivityType { letters, words, practice }

sealed class ExerciseDefinition {
  const ExerciseDefinition({
    required this.id,
    required this.title,
    required this.type,
  });

  factory ExerciseDefinition.fromJson(Map<String, dynamic> json) {
    final type = ActivityType.values.byName(json['type'] as String);
    return type == ActivityType.letters
        ? LetterExercise.fromJson(json)
        : TypingExercise.fromJson(json);
  }

  final String id;
  final String title;
  final ActivityType type;
  Iterable<String> get audioAssets;
}

class TypingExercise extends ExerciseDefinition {
  TypingExercise({
    required super.id,
    required super.title,
    required super.type,
    required List<TypingUnit> units,
    this.allowedLetters,
  }) : units = List.unmodifiable(units) {
    if (type == ActivityType.letters ||
        units.isEmpty ||
        units.map((unit) => unit.id).toSet().length != units.length) {
      throw FormatException('Invalid typing exercise: $id');
    }
    if (type == ActivityType.words) {
      if (allowedLetters == null || allowedLetters!.isEmpty) {
        throw FormatException('Missing allowed letters: $id');
      }
      final permitted = allowedLetters!.toLowerCase().split('').toSet();
      for (final unit in units) {
        if (unit.words.length != 1 ||
            unit.text != unit.words.single ||
            !unit.text.toLowerCase().split('').every(permitted.contains)) {
          throw FormatException(
            'Word drill uses an invalid target: ${unit.text}',
          );
        }
      }
    }
  }

  factory TypingExercise.fromJson(Map<String, dynamic> json) => TypingExercise(
    id: json['id'] as String,
    title: json['title'] as String,
    type: ActivityType.values.byName(json['type'] as String),
    allowedLetters: json['allowedLetters'] as String?,
    units: (json['units'] as List)
        .map((unit) => TypingUnit.fromJson(unit as Map<String, dynamic>))
        .toList(),
  );

  final List<TypingUnit> units;
  final String? allowedLetters;
  bool get isWordDrill => type == ActivityType.words;
  @override
  Iterable<String> get audioAssets =>
      units.expand((unit) => unit.audioAssets(readSentence: !isWordDrill));
}

class LetterStep {
  LetterStep({
    required this.id,
    required this.key,
    required this.instruction,
    required this.retry,
    required this.success,
    required this.complete,
    required this.requiredSuccesses,
  }) {
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(id) ||
        key.runes.length != 1 ||
        requiredSuccesses < 1) {
      throw FormatException('Invalid teaching step: $id');
    }
  }

  factory LetterStep.fromJson(Map<String, dynamic> json) => LetterStep(
    id: json['id'] as String,
    key: json['key'] as String,
    instruction: json['instruction'] as String,
    retry: json['retry'] as String,
    success: json['success'] as String,
    complete: json['complete'] as String,
    requiredSuccesses: json['requiredSuccesses'] as int,
  );

  final String id;
  final String key;
  final String instruction;
  final String retry;
  final String success;
  final String complete;
  final int requiredSuccesses;
  String audio(String cue) => 'assets/audio/step_${id}_$cue.wav';
  Iterable<String> get audioAssets => [
    for (final cue in ['instruction', 'retry', 'success', 'complete'])
      audio(cue),
  ];
}

class LetterExercise extends ExerciseDefinition {
  LetterExercise({
    required super.id,
    required super.title,
    required List<LetterStep> steps,
  }) : steps = List.unmodifiable(steps),
       super(type: ActivityType.letters) {
    if (steps.isEmpty ||
        steps.map((step) => step.id).toSet().length != steps.length) {
      throw FormatException('Invalid letter exercise: $id');
    }
  }

  factory LetterExercise.fromJson(Map<String, dynamic> json) => LetterExercise(
    id: json['id'] as String,
    title: json['title'] as String,
    steps: (json['steps'] as List)
        .map((step) => LetterStep.fromJson(step as Map<String, dynamic>))
        .toList(),
  );

  final List<LetterStep> steps;
  @override
  Iterable<String> get audioAssets => steps.expand((step) => step.audioAssets);
}
