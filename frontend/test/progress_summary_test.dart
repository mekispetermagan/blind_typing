import 'package:blind_typing/api/progress_repository.dart';
import 'package:blind_typing/models/progress_summary.dart';
import 'package:blind_typing/screens/progress_screen.dart';
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
  test('weeks start Monday and interruptions affect letter totals but not completed count', () {
    final progress = StudentProgress(
      name: 'Test',
      attempts: [
        attempt(DateTime(2026, 11, 16), 'completed', 120000, [
          const KeyProgress(key: 'ö', correct: 3, incorrect: 1),
        ]),
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
    expect(result.days[0].date, DateTime(2026, 11, 16));
    expect(result.days[0].completed, 1);
    expect(result.days[0].interrupted, 1);
    expect(result.days[1].completed, 0);
    expect(result.days[1].interrupted, 1);
    expect(result.days[2].completed, 0); // In-progress attempts are excluded.
    expect(result.weeks.first.start, DateTime(2026, 11, 16));
    expect(result.weeks.first.completed, 1);
    expect(result.weeks.first.durationMs, 120000);
    expect(result.weeks[1].completed, 1);
    expect(result.keys.single.correct, 3);
    expect(result.keys.single.incorrect, 3);
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
    final today = DateTime.now().weekday - 1;
    expect(charts.first.data.barGroups[today].barRods.single.toY, 1);
    expect(charts.last.data.barGroups.single.barRods.single.toY, 4);
    expect(
      charts.last.data.barGroups.single.barRods.single.rodStackItems.length,
      2,
    );
    expect(find.text('Befejezett feladatok: 1'), findsOneWidget);
    expect(
      find.text('Aktív gyakorlási idő: 2 perc 0 másodperc'),
      findsOneWidget,
    );
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
    expect(find.text('A haladási adatok nem tölthetők be.'), findsOneWidget);
    expect(find.text('Újrapróbálás'), findsOneWidget);
  });
}
