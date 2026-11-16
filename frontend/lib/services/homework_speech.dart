import '../api/homework_repository.dart';
import 'audio_service.dart';
import 'practice_feedback.dart';

String homeworkCue(String name) => switch (name) {
  'return' => 'assets/audio/menu_previous.wav',
  'teacher' => 'assets/audio/menu_area_trainer.wav',
  'hour' => 'assets/audio/reach_ow_o_08_word_0.wav',
  _ => 'assets/audio/homework_$name.wav',
};
String homeworkStatus(HomeworkData hw) => hw.expired
    ? (hw.submitted ? 'Lejárt, beadva' : 'Lejárt, nincs beadva')
    : (hw.submitted ? 'Nyitott, beadva' : 'Nyitott, nincs beadva');
String homeworkStatusAudio(HomeworkData hw) => homeworkCue(
  'status_${hw.expired ? 'expired' : 'open'}_${hw.submitted ? 'submitted' : 'unsubmitted'}',
);
String dateText(DateTime date) =>
    '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
List<String> dateAudio(DateTime date) => [
  ...PracticeFeedback.number(date.year),
  'assets/audio/progress_month_${date.month}.wav',
  ...PracticeFeedback.number(date.day),
  ...PracticeFeedback.number(date.hour),
  homeworkCue('hour'),
  ...PracticeFeedback.number(date.minute),
  'assets/audio/result_minute.wav',
];
List<String> teacherAudio(HomeworkData hw) {
  final revision = hw.trainerAudioRevision;
  if (revision != null && RegExp(r'^[0-9a-f]{16}$').hasMatch(revision)) {
    return ['assets/audio/homework_teacher_${hw.id}_$revision.wav'];
  }
  final result = [
    for (final c in hw.trainerName.split(''))
      if (c.trim().isNotEmpty) AudioCues.letter(c),
  ];
  return result.isEmpty ? [AudioCues.unknownCharacter] : result;
}

List<String> attemptAudio(HomeworkAttemptData attempt) => [
  'assets/audio/progress_date.wav',
  ...dateAudio(attempt.submittedAt),
  'assets/audio/result_time.wav',
  ...PracticeFeedback.number(attempt.durationMs ~/ 60000, beforeUnit: true),
  'assets/audio/result_minute.wav',
  ...PracticeFeedback.number(
    (attempt.durationMs ~/ 1000) % 60,
    beforeUnit: true,
  ),
  'assets/audio/result_second.wav',
  'assets/audio/result_errors.wav',
  ...PracticeFeedback.number(attempt.mistakes),
  if (attempt.score case final score?) ...[
    'assets/audio/result_score.wav',
    ...PracticeFeedback.number(score),
  ],
  for (final key in attempt.keys) ...[
    AudioCues.letter(key.key),
    'assets/audio/progress_correct.wav',
    ...PracticeFeedback.number(key.correct),
    'assets/audio/progress_incorrect.wav',
    ...PracticeFeedback.number(key.incorrect),
  ],
];
List<String> homeworkAudio(HomeworkData hw, {required bool trainer}) => [
  homeworkCue('teacher'),
  ...teacherAudio(hw),
  homeworkCue('deadline'),
  ...dateAudio(hw.deadline),
  homeworkStatusAudio(hw),
  for (final entry in hw.entries) ...[
    homeworkCue('entry'),
    if (entry.audio case final clip?)
      clip
    else ...[
      for (final char in entry.text.split(''))
        if (char.trim().isNotEmpty) AudioCues.letter(char),
    ],
    homeworkCue('repetitions'),
    ...PracticeFeedback.number(entry.repetitions),
  ],
  if (trainer && hw.attempts.isEmpty) homeworkCue('no_attempt'),
  if (trainer && hw.attempts.isNotEmpty) ...[
    homeworkCue('latest'),
    ...attemptAudio(hw.attempts.first),
  ],
  if (trainer && hw.attempts.isNotEmpty) homeworkCue('earlier'),
  if (trainer && hw.expired) homeworkCue('reopen'),
];
