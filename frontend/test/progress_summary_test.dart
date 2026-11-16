import 'package:blind_typing/api/progress_repository.dart';
import 'package:blind_typing/models/progress_summary.dart';
import 'package:blind_typing/screens/progress_screen.dart';
import 'package:blind_typing/widgets/progress/bar_charts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

ProgressAttempt attempt(
  DateTime date,
  String status,
  int duration,
  List<KeyProgress> keys,
) => ProgressAttempt(
  title: 'Ö gyakorlás',
  startedAt: date,
  status: status,
  activeDurationMs: duration,
  mistakeCount: 3,
  keys: keys,
);

void main() {
  test(
    'rolling week includes seven days and interruptions affect letter totals',
    () {
      final progress = StudentProgress(
        name: 'Test',
        attempts: [
          attempt(DateTime(2026, 11, 12), 'completed', 2000, []),
          attempt(DateTime(2026, 11, 11, 23, 59), 'completed', 3000, []),
          attempt(DateTime(2026, 11, 19), 'completed', 4000, []),
          attempt(DateTime(2026, 11, 16), 'completed', 120000, [
            const KeyProgress(key: 'ö', correct: 3, incorrect: 1),
          ]),
          attempt(DateTime(2026, 11, 16, 10), 'completed', 30000, []),
          attempt(DateTime(2026, 11, 16, 12), 'interrupted', 1000, []),
          attempt(DateTime(2026, 11, 17), 'interrupted', 60000, [
            const KeyProgress(key: 'ö', correct: 0, incorrect: 2),
          ]),
          attempt(DateTime(2026, 11, 15, 23, 59), 'completed', 1000, []),
          attempt(DateTime(2026, 11, 18), 'in_progress', 1000, [
            const KeyProgress(key: 'ö', correct: 10, incorrect: 0),
          ]),
        ],
      );
      final result = ProgressSummary(progress, DateTime(2026, 11, 18));
      expect(result.days.length, 7);
      expect(result.days.first.date, DateTime(2026, 11, 12));
      expect(result.days.last.date, DateTime(2026, 11, 18));
      expect(result.days.first.completed, 1);
      expect(result.days[4].completed, 2);
      expect(result.days[4].durationMs, 150000);
      expect(result.days.first.durationMs, 2000);
      expect(result.days[1].durationMs, 0);
      expect(result.days[4].interrupted, 1);
      expect(result.days[5].interrupted, 1);
      expect(result.days[5].durationMs, 0);
      // In-progress attempts are excluded.
      expect(result.days.last.completed, 0);
      expect(result.days.last.durationMs, 0);
      expect(result.weeks.first.start, DateTime(2026, 11, 12));
      expect(result.weeks.first.completed, 4);
      expect(result.weeks.first.durationMs, 153000);
      expect(
        result.days.fold<int>(0, (sum, day) => sum + day.durationMs),
        result.weeks.first.durationMs,
      );
      expect(result.weeks[1].start, DateTime(2026, 11, 5));
      expect(result.weeks[1].completed, 1);
      expect(result.keys.single.correct, 3);
      expect(result.keys.single.incorrect, 3);
    },
  );

  test('calendar day boundaries remain consecutive across daylight saving', () {
    final progress = StudentProgress(
      name: 'Test',
      attempts: [
        attempt(DateTime(2026, 3, 28, 23, 59), 'completed', 1, []),
        attempt(DateTime(2026, 3, 29), 'completed', 1, []),
        attempt(DateTime(2026, 3, 30), 'completed', 1, []),
      ],
    );
    final result = ProgressSummary(progress, DateTime(2026, 3, 30, 12));
    expect(result.days.first.date, DateTime(2026, 3, 24));
    expect(result.days.last.date, DateTime(2026, 3, 30));
    expect(result.days.sublist(4).map((day) => day.completed), [1, 1, 1]);
    expect(result.weeks.first.completed, 3);
  });

  testWidgets('chart weekday labels follow the rolling dates', (tester) async {
    final summary = ProgressSummary(
      const StudentProgress(name: 'Test', attempts: []),
      DateTime(2026, 11, 18),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WeeklyActivityChart(days: summary.days)),
      ),
    );
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    final titles = chart.data.titlesData.bottomTitles.sideTitles;
    final meta = TitleMeta(
      min: 0,
      max: 6,
      parentAxisSize: 300,
      axisPosition: 0,
      appliedInterval: 1,
      sideTitles: titles,
      formattedValue: '',
      axisSide: AxisSide.bottom,
      rotationQuarterTurns: 0,
    );
    final labels = [
      for (var i = 0; i < 7; i++)
        ((titles.getTitlesWidget(i.toDouble(), meta) as SideTitleWidget).child
                as Text)
            .data,
    ];
    expect(labels, ['Cs', 'P', 'Szo', 'V', 'H', 'K', 'Sze']);
  });

  testWidgets('page shows practice totals, letter data and recent attempts', (
    tester,
  ) async {
    final progress = StudentProgress(
      name: 'Mekis Péter',
      attempts: [
        attempt(DateTime.now(), 'completed', 120000, [
          const KeyProgress(key: 'ö', correct: 3, incorrect: 1),
        ]),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: ProgressScreen(loadProgress: () async => progress)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BarChart), findsNWidgets(2));
    final charts = tester.widgetList<BarChart>(find.byType(BarChart)).toList();
    expect(charts.first.data.barGroups.last.barRods.single.toY, 1);
    expect(charts.last.data.barGroups.single.barRods.single.toY, 4);
    expect(
      charts.last.data.barGroups.single.barRods.single.rodStackItems.length,
      2,
    );
    expect(find.text('Befejezett feladatok: 1'), findsOneWidget);
    expect(
      find.text('Az elmúlt 7 nap: elkezdett feladatok nap szerint'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Befejezett: 1 · Megszakított: 0\nAktív gyakorlási idő: 2 perc',
      ),
      findsOneWidget,
    );
    expect(find.text('Aktív gyakorlási idő: 2 perc'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Betűstatisztika'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      find.text('Elsőre helyes: 3 · Elsőre hibás: 1 · Összesen: 4'),
      findsOneWidget,
    );
    expect(find.text('75% helyes'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Legutóbbi feladatok'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ö gyakorlás'), findsOneWidget);
  });

  testWidgets('page displays empty and error states', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProgressScreen(
          loadProgress: () async =>
              const StudentProgress(name: 'Test', attempts: []),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Még nincs betűstatisztika.'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: ProgressScreen(
          key: const ValueKey('error'),
          loadProgress: () async => throw StateError('offline'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.textContaining('A haladási adatok nem tölthetők be.'),
      findsOneWidget,
    );
    expect(find.text('Újrapróbálás'), findsOneWidget);
  });
}
