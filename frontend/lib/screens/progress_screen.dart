import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/progress_repository.dart';
import '../models/progress_summary.dart';
import '../widgets/progress/bar_charts.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, this.loadProgress, this.onBack});
  final Future<StudentProgress> Function()? loadProgress;
  final VoidCallback? onBack;

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  late Future<StudentProgress> _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() =>
      _progress = (widget.loadProgress ?? ProgressRepository().load)();
  String _date(DateTime date) =>
      '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')}';
  String _time(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    return '${seconds ~/ 60} perc ${seconds % 60} másodperc';
  }

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape &&
          widget.onBack != null) {
        widget.onBack!();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Haladásom'),
        leading: widget.onBack == null
            ? null
            : IconButton(
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Vissza',
              ),
      ),
      body: FutureBuilder<StudentProgress>(
        future: _progress,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('A haladási adatok nem tölthetők be.'),
                  TextButton(
                    onPressed: () => setState(_load),
                    child: const Text('Újrapróbálás'),
                  ),
                ],
              ),
            );
          }
          final progress = snapshot.data!;
          final summary = ProgressSummary(progress, DateTime.now());
          final current = summary.weeks.first;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 850),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress.name,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 24),
                    _section(context, 'Ezen a héten'),
                    Text('Befejezett feladatok: ${current.completed}'),
                    Text('Aktív gyakorlási idő: ${_time(current.durationMs)}'),
                    const SizedBox(height: 24),
                    _section(context, 'Heti gyakorlás'),
                    const Text(
                      'Aktuális hét: elkezdett feladatok nap szerint, hétfőtől vasárnapig',
                    ),
                    WeeklyActivityChart(days: summary.days),
                    const SizedBox(height: 16),
                    const Text('Heti összesítés: befejezett feladatok'),
                    for (final week in summary.weeks)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${_date(week.start)} – ${_date(DateTime(week.start.year, week.start.month, week.start.day + 6))}',
                        ),
                        trailing: Text('${week.completed} feladat'),
                      ),
                    const SizedBox(height: 24),
                    _section(context, 'Betűstatisztika'),
                    const Text(
                      'Első próbálkozásra helyes és hibás találatok; minden befejezett vagy megszakított feladatból.',
                    ),
                    if (summary.keys.isNotEmpty)
                      LetterStatisticsChart(keysData: summary.keys),
                    if (summary.keys.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Még nincs betűstatisztika.'),
                      ),
                    for (final key in summary.keys)
                      ListTile(
                        dense: true,
                        title: Text(key.key.toUpperCase()),
                        subtitle: Text(
                          'Elsőre helyes: ${key.correct} · Elsőre hibás: ${key.incorrect} · Összesen: ${key.total}',
                        ),
                        trailing: Text(
                          key.total == 0
                              ? 'Nincs adat'
                              : '${(100 * key.correct / key.total).toStringAsFixed(0)}% helyes',
                        ),
                      ),
                    const SizedBox(height: 24),
                    _section(context, 'Legutóbbi feladatok'),
                    if (progress.attempts.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Még nincsenek feladatok.'),
                      ),
                    for (final attempt in progress.attempts.take(10))
                      ListTile(
                        title: Text(attempt.title),
                        subtitle: Text(
                          '${_date(attempt.startedAt)} · ${attempt.status == 'completed' ? 'Befejezve' : 'Megszakítva'}\nAktív idő: ${_time(attempt.activeDurationMs)} · Hibák: ${attempt.mistakeCount}',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );

  Widget _section(BuildContext context, String title) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(title, style: Theme.of(context).textTheme.headlineSmall),
  );
}
