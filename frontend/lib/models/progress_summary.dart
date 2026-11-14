import '../api/progress_repository.dart';

class WeekProgress {
  const WeekProgress(this.start, this.completed, this.durationMs);
  final DateTime start;
  final int completed;
  final int durationMs;
}

class DayProgress {
  const DayProgress(this.date, this.completed, this.interrupted);
  final DateTime date;
  final int completed;
  final int interrupted;
}

class ProgressSummary {
  ProgressSummary(StudentProgress progress, DateTime now) {
    final today = now.toLocal();
    final monday = DateTime(
      today.year,
      today.month,
      today.day - today.weekday + 1,
    );
    days = List.generate(7, (index) {
      final start = DateTime(monday.year, monday.month, monday.day + index);
      final end = DateTime(start.year, start.month, start.day + 1);
      final dayAttempts = progress.attempts.where(
        (attempt) =>
            !attempt.startedAt.isBefore(start) &&
            attempt.startedAt.isBefore(end),
      );
      return DayProgress(
        start,
        dayAttempts.where((attempt) => attempt.status == 'completed').length,
        dayAttempts.where((attempt) => attempt.status == 'interrupted').length,
      );
    });
    weeks = List.generate(8, (index) {
      final start = DateTime(monday.year, monday.month, monday.day - 7 * index);
      final end = DateTime(start.year, start.month, start.day + 7);
      final completed = progress.attempts.where(
        (attempt) =>
            attempt.status == 'completed' &&
            !attempt.startedAt.isBefore(start) &&
            attempt.startedAt.isBefore(end),
      );
      return WeekProgress(
        start,
        completed.length,
        completed.fold(0, (sum, attempt) => sum + attempt.activeDurationMs),
      );
    });
    final counts = <String, (int, int)>{};
    for (final attempt in progress.attempts) {
      if (attempt.status != 'completed' && attempt.status != 'interrupted') {
        continue;
      }
      for (final key in attempt.keys) {
        final previous = counts[key.key] ?? (0, 0);
        counts[key.key] = (
          previous.$1 + key.correct,
          previous.$2 + key.incorrect,
        );
      }
    }
    keys = [
      for (final entry in counts.entries)
        KeyProgress(
          key: entry.key,
          correct: entry.value.$1,
          incorrect: entry.value.$2,
        ),
    ]..sort((a, b) => a.key.compareTo(b.key));
  }
  late final List<DayProgress> days;
  late final List<WeekProgress> weeks;
  late final List<KeyProgress> keys;
}
