import 'dart:convert';

import '../services/audio_service.dart';
import 'backend.dart';

class TrainerStudent {
  const TrainerStudent({
    required this.id,
    required this.name,
    this.nameAudioRevision,
  });
  factory TrainerStudent.fromJson(Map<String, dynamic> json) {
    final revision = json['name_audio_revision'] as String?;
    if (revision != null && !RegExp(r'^[0-9a-f]{16}$').hasMatch(revision)) {
      throw const FormatException('Invalid name audio revision');
    }
    return TrainerStudent(
      id: json['id'] as int,
      name: json['name'] as String,
      nameAudioRevision: revision,
    );
  }
  final int id;
  final String name;
  final String? nameAudioRevision;

  List<String> get nameAudio {
    final revision = nameAudioRevision;
    if (revision != null)
      return ['assets/audio/student_name_${id}_$revision.wav'];
    final clips = [
      for (final character in name.split(''))
        if (character.trim().isNotEmpty) AudioCues.letter(character),
    ];
    return clips.isEmpty ? [AudioCues.unknownCharacter] : clips;
  }
}

class TrainerRepository {
  Future<List<TrainerStudent>> students() async {
    final response = await backendGet('/api/trainer/students');
    if (response.statusCode != 200) {
      await response.drain<void>();
      throw StateError('Student request failed: ${response.statusCode}');
    }
    final body = await response.transform(utf8.decoder).join();
    return (jsonDecode(body) as List)
        .map((value) => TrainerStudent.fromJson(value as Map<String, dynamic>))
        .toList();
  }
}
