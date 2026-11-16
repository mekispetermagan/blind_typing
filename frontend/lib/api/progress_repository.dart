import 'dart:convert';

import 'backend.dart';

class KeyProgress {
  const KeyProgress({
    required this.key,
    required this.correct,
    required this.incorrect,
  });
  factory KeyProgress.fromJson(Map<String, dynamic> json) => KeyProgress(
    key: json['key'] as String,
    correct: json['correct'] as int,
    incorrect: json['incorrect'] as int,
  );
  final String key;
  final int correct;
  final int incorrect;
  int get total => correct + incorrect;
}

class ProgressAttempt {
  const ProgressAttempt({
    required this.title,
    this.activityId,
    required this.startedAt,
    required this.status,
    required this.activeDurationMs,
    required this.mistakeCount,
    this.score,
    this.titleAudio = const [],
    required this.keys,
  });
  factory ProgressAttempt.fromJson(Map<String, dynamic> json) =>
      ProgressAttempt(
        title: json['title'] as String,
        activityId: json['activity_id'] as String?,
        startedAt: DateTime.parse(json['started_at'] as String).toLocal(),
        status: json['status'] as String,
        activeDurationMs: json['active_duration_ms'] as int,
        mistakeCount: json['mistake_count'] as int,
        score: json['score'] as int?,
        titleAudio: (json['title_audio'] as List? ?? []).cast<String>(),
        keys: (json['keys'] as List<dynamic>)
            .map((item) => KeyProgress.fromJson(item as Map<String, dynamic>))
            .toList(),
      );
  final String title;
  final String? activityId;
  final DateTime startedAt;
  final String status;
  final int activeDurationMs;
  final int mistakeCount;
  final int? score;
  final List<String> titleAudio;
  final List<KeyProgress> keys;
}

class StudentProgress {
  const StudentProgress({required this.name, required this.attempts});
  factory StudentProgress.fromJson(Map<String, dynamic> json) =>
      StudentProgress(
        name: json['name'] as String,
        attempts: (json['attempts'] as List<dynamic>)
            .map(
              (item) => ProgressAttempt.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );
  final String name;
  final List<ProgressAttempt> attempts;
}

class ProgressRepository {
  Future<StudentProgress> load({int? studentId}) async {
    final path = studentId == null
        ? '/api/progress'
        : '/api/trainer/students/$studentId/progress';
    final response = await backendGet(path);
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw StateError('Progress request failed: ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join();
    return StudentProgress.fromJson(jsonDecode(body) as Map<String, dynamic>);
  }
}
