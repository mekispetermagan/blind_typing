import 'dart:convert';
import 'dart:io';

import 'backend.dart';
import 'progress_repository.dart';

class HomeworkEntryData {
  const HomeworkEntryData(this.text, this.repetitions, {this.audio});
  factory HomeworkEntryData.fromJson(Map<String, dynamic> data) =>
      HomeworkEntryData(data['text'] as String, data['repetitions'] as int);
  final String text;
  final int repetitions;
  final String? audio;
  Map<String, dynamic> toJson() => {'text': text, 'repetitions': repetitions};
}

class HomeworkAttemptData {
  const HomeworkAttemptData({
    required this.id,
    required this.submittedAt,
    required this.durationMs,
    required this.mistakes,
    required this.score,
    required this.keys,
  });
  factory HomeworkAttemptData.fromJson(Map<String, dynamic> data) =>
      HomeworkAttemptData(
        id: data['id'] as String,
        submittedAt: DateTime.parse(data['submitted_at'] as String).toLocal(),
        durationMs: data['active_duration_ms'] as int,
        mistakes: data['mistake_count'] as int,
        score: data['score'] as int?,
        keys: (data['keys'] as List)
            .map((x) => KeyProgress.fromJson(x as Map<String, dynamic>))
            .toList(),
      );
  final String id;
  final DateTime submittedAt;
  final int durationMs;
  final int mistakes;
  final int? score;
  final List<KeyProgress> keys;
}

class HomeworkData {
  const HomeworkData({
    required this.id,
    required this.trainerName,
    required this.deadline,
    required this.expired,
    required this.submitted,
    required this.entries,
    this.trainerAudioRevision,
    this.attempts = const [],
    this.exercise,
  });
  factory HomeworkData.fromJson(Map<String, dynamic> data) => HomeworkData(
    id: data['id'] as String,
    trainerName: data['trainer_name'] as String,
    trainerAudioRevision: data['trainer_audio_revision'] as String?,
    deadline: DateTime.parse(data['deadline'] as String).toLocal(),
    expired: data['expired'] as bool,
    submitted: data['submitted'] as bool,
    entries: (data['entries'] as List)
        .map((x) => HomeworkEntryData.fromJson(x as Map<String, dynamic>))
        .toList(),
    attempts: (data['attempts'] as List? ?? [])
        .map((x) => HomeworkAttemptData.fromJson(x as Map<String, dynamic>))
        .toList(),
    exercise: data['exercise'] as Map<String, dynamic>?,
  );
  final String id;
  final String trainerName;
  final String? trainerAudioRevision;
  final DateTime deadline;
  final bool expired;
  final bool submitted;
  final List<HomeworkEntryData> entries;
  final List<HomeworkAttemptData> attempts;
  final Map<String, dynamic>? exercise;
}

class HomeworkRepository {
  Future<dynamic> _get(String path) async {
    final response = await backendGet(path);
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode != 200)
      throw StateError('Request failed: ${response.statusCode}');
    return jsonDecode(body);
  }

  Future<dynamic> _post(String path, Map<String, dynamic> body) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.postUrl(Uri.parse('$backendUrl$path'));
      final token = backendToken;
      if (token != null)
        request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(
        const Duration(minutes: 5),
      );
      final result = await response.transform(utf8.decoder).join();
      if (response.statusCode == 401 && token != null)
        onUnauthorized?.call(token);
      if (response.statusCode != 200)
        throw StateError('Request failed: ${response.statusCode}');
      return jsonDecode(result);
    } finally {
      client.close(force: true);
    }
  }

  Future<List<HomeworkData>> list({int? studentId}) async {
    final path = studentId == null
        ? '/api/homeworks'
        : '/api/trainer/students/$studentId/homeworks';
    return (await _get(path) as List)
        .map((x) => HomeworkData.fromJson(x as Map<String, dynamic>))
        .toList();
  }

  Future<HomeworkData> load(String id) async => HomeworkData.fromJson(
    await _get('/api/homeworks/$id') as Map<String, dynamic>,
  );
  Future<void> create(
    int studentId,
    DateTime deadline,
    List<HomeworkEntryData> entries, {
    String? requestId,
  }) async {
    await _post('/api/trainer/students/$studentId/homeworks', {
      if (requestId != null) 'id': requestId,
      'deadline': deadline.toUtc().toIso8601String(),
      'entries': entries.map((x) => x.toJson()).toList(),
    });
  }

  Future<void> reopen(String id, DateTime deadline) async {
    await _post('/api/trainer/homeworks/$id/reopen', {
      'deadline': deadline.toUtc().toIso8601String(),
    });
  }
}
