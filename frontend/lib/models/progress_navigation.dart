import '../api/progress_repository.dart';
import '../services/audio_service.dart';
import '../services/practice_feedback.dart';
import 'progress_summary.dart';

String progressCue(String name) => 'assets/audio/progress_$name.wav';

class ProgressItem {
  const ProgressItem({
    required this.title,
    required this.audio,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final String? trailing;
  final List<String> audio;
}

class ProgressSection {
  const ProgressSection(this.title, this.audio, this.items);
  final String title;
  final String audio;
  final List<ProgressItem> items;
}

class ProgressNavigation {
  ProgressNavigation(
    StudentProgress progress,
    DateTime now,
    Map<String, List<String>> activityAudio, {
    String backTitle = 'Vissza a főmenübe',
    String backAudio = 'assets/audio/progress_return_main.wav',
  }) : summary = ProgressSummary(progress, now) {
    final current = summary.weeks.first;
    final todayItems = [
      ProgressItem(
        title: 'Befejezett feladatok: ${current.completed}',
        audio: [
          progressCue('completed'),
          ...PracticeFeedback.number(current.completed),
        ],
      ),
      ProgressItem(
        title: 'Aktív gyakorlási idő: ${_durationMinutes(current.durationMs)}',
        audio: [
          progressCue('duration'),
          ..._durationMinutesAudio(current.durationMs),
        ],
      ),
    ];
    final dailyItems = [
      for (final day in summary.days)
        ProgressItem(
          title: '${_weekdays[day.date.weekday - 1]} · ${_date(day.date)}',
          subtitle:
              'Befejezett: ${day.completed} · Megszakított: ${day.interrupted}\n'
              'Aktív gyakorlási idő: ${_durationMinutes(day.durationMs)}',
          audio: [
            progressCue('day_${day.date.weekday}'),
            ..._dateAudio(day.date),
            progressCue('completed'),
            ...PracticeFeedback.number(day.completed),
            progressCue('interrupted'),
            ...PracticeFeedback.number(day.interrupted),
            progressCue('duration'),
            ..._durationMinutesAudio(day.durationMs),
          ],
        ),
    ];
    final weekItems = [
      for (final week in summary.weeks)
        ProgressItem(
          title:
              '${_date(week.start)} – ${_date(DateTime(week.start.year, week.start.month, week.start.day + 6))}',
          trailing: '${week.completed} feladat',
          audio: [
            progressCue('week'),
            ..._dateAudio(week.start),
            progressCue('until'),
            ..._dateAudio(
              DateTime(week.start.year, week.start.month, week.start.day + 6),
            ),
            progressCue('completed'),
            ...PracticeFeedback.number(week.completed),
          ],
        ),
    ];
    final letterItems = [
      for (final key in summary.keys)
        ProgressItem(
          title: key.key.toUpperCase(),
          subtitle:
              'Elsőre helyes: ${key.correct} · Elsőre hibás: ${key.incorrect} · Összesen: ${key.total}',
          trailing: key.total == 0
              ? 'Nincs adat'
              : '${(100 * key.correct / key.total).toStringAsFixed(0)}% helyes',
          audio: [
            AudioCues.letter(key.key),
            progressCue('correct'),
            ...PracticeFeedback.number(key.correct),
            progressCue('incorrect'),
            ...PracticeFeedback.number(key.incorrect),
            progressCue('total'),
            ...PracticeFeedback.number(key.total),
            if (key.total > 0) ...[
              ...PracticeFeedback.number(
                (100 * key.correct / key.total).round(),
              ),
              progressCue('percent'),
            ],
          ],
        ),
    ];
    ProgressItem attemptItem(ProgressAttempt attempt) => ProgressItem(
      title: attempt.title,
      subtitle:
          '${_date(attempt.startedAt)} · ${attempt.status == 'completed' ? 'Befejezve' : 'Megszakítva'}\nAktív idő: ${_duration(attempt.activeDurationMs)} · Hibák: ${attempt.mistakeCount}${attempt.score == null ? '' : ' · Pontszám: ${attempt.score}'}',
      audio: [
        progressCue('activity'),
        if (attempt.titleAudio.isNotEmpty)
          ...attempt.titleAudio
        else if (activityAudio[attempt.activityId] case final clips?)
          ...clips
        else
          ..._spell(attempt.title),
        progressCue('date'),
        ..._dateAudio(attempt.startedAt),
        progressCue(attempt.status == 'completed' ? 'finished' : 'stopped'),
        progressCue('duration'),
        ..._durationAudio(attempt.activeDurationMs),
        'assets/audio/result_errors.wav',
        ...PracticeFeedback.number(attempt.mistakeCount),
        if (attempt.score case final score?) ...[
          'assets/audio/result_score.wav',
          ...PracticeFeedback.number(score),
        ],
      ],
    );
    final recentItems = [
      for (final attempt in progress.attempts.take(10)) attemptItem(attempt),
    ];
    final homeworkItems = [
      for (final attempt in progress.attempts)
        if (attempt.activityId?.startsWith('homework_') == true)
          attemptItem(attempt),
    ];
    sections = [
      ProgressSection(
        'Az elmúlt 7 napban',
        progressCue('section_week'),
        todayItems,
      ),
      ProgressSection('Heti gyakorlás', progressCue('section_activity'), [
        ...dailyItems,
        ...weekItems,
      ]),
      ProgressSection(
        'Betűstatisztika',
        progressCue('section_letters'),
        letterItems.isNotEmpty
            ? letterItems
            : [
                ProgressItem(
                  title: 'Még nincs betűstatisztika.',
                  audio: [progressCue('empty_letters')],
                ),
              ],
      ),
      ProgressSection(
        'Legutóbbi feladatok',
        progressCue('section_recent'),
        recentItems.isNotEmpty
            ? recentItems
            : [
                ProgressItem(
                  title: 'Még nincsenek feladatok.',
                  audio: [progressCue('empty_recent')],
                ),
              ],
      ),
      if (homeworkItems.isNotEmpty)
        ProgressSection(
          'Házi feladatok',
          'assets/audio/menu_homeworks.wav',
          homeworkItems,
        ),
      ProgressSection(backTitle, backAudio, [
        ProgressItem(title: backTitle, audio: [backAudio]),
      ]),
    ];
  }
  final ProgressSummary summary;
  late final List<ProgressSection> sections;
  Iterable<String> get allAudio => [
    progressCue('help'),
    for (final section in sections) ...[
      section.audio,
      for (final item in section.items) ...item.audio,
    ],
  ];
}

const _weekdays = [
  'Hétfő',
  'Kedd',
  'Szerda',
  'Csütörtök',
  'Péntek',
  'Szombat',
  'Vasárnap',
];
String _date(DateTime date) =>
    '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
String _durationMinutes(int milliseconds) => '${milliseconds ~/ 60000} perc';

String _duration(int milliseconds) {
  final seconds = milliseconds ~/ 1000;
  return '${seconds ~/ 60} perc ${seconds % 60} másodperc';
}

Iterable<String> _dateAudio(DateTime date) sync* {
  yield* PracticeFeedback.number(date.year);
  yield progressCue('month_${date.month}');
  yield* PracticeFeedback.number(date.day);
}

Iterable<String> _durationMinutesAudio(int milliseconds) sync* {
  yield* PracticeFeedback.number(milliseconds ~/ 60000, beforeUnit: true);
  yield 'assets/audio/result_minute.wav';
}

Iterable<String> _durationAudio(int milliseconds) sync* {
  final seconds = milliseconds ~/ 1000;
  yield* _durationMinutesAudio(milliseconds);
  yield* PracticeFeedback.number(seconds % 60, beforeUnit: true);
  yield 'assets/audio/result_second.wav';
}

Iterable<String> _spell(String text) sync* {
  for (final char in text.toLowerCase().split('')) {
    if (AudioCues.alphabet.contains(char) ||
        RegExp(r'^[0-9]$').hasMatch(char)) {
      yield AudioCues.letter(char);
    }
  }
}
