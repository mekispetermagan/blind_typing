import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../api/progress_repository.dart';
import '../../models/progress_summary.dart';

const _green = Color(0xff52c77b);
const _red = Color(0xffff7777);
const _weekdayLabels = ['H', 'K', 'Sze', 'Cs', 'P', 'Szo', 'V'];

class WeeklyActivityChart extends StatelessWidget {
  const WeeklyActivityChart({super.key, required this.days});
  final List<DayProgress> days;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Legend(green: 'Befejezett', red: 'Megszakított'),
      const SizedBox(height: 12),
      _StackedBars(
        labels: [for (final day in days) _weekdayLabels[day.date.weekday - 1]],
        values: [for (final day in days) (day.completed, day.interrupted)],
        greenLabel: 'Befejezett',
        redLabel: 'Megszakított',
      ),
    ],
  );
}

class LetterStatisticsChart extends StatelessWidget {
  const LetterStatisticsChart({super.key, required this.keysData});
  final List<KeyProgress> keysData;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const _Legend(green: 'Elsőre helyes', red: 'Elsőre hibás'),
      const SizedBox(height: 12),
      _StackedBars(
        labels: [for (final key in keysData) key.key.toUpperCase()],
        values: [for (final key in keysData) (key.correct, key.incorrect)],
        greenLabel: 'Elsőre helyes',
        redLabel: 'Elsőre hibás',
        scrollable: true,
      ),
    ],
  );
}

class _Legend extends StatelessWidget {
  const _Legend({required this.green, required this.red});
  final String green;
  final String red;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 24,
    runSpacing: 8,
    children: [_item(_green, green), _item(_red, red)],
  );
  Widget _item(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 12, height: 12, color: color),
      const SizedBox(width: 6),
      Text(label),
    ],
  );
}

class _StackedBars extends StatelessWidget {
  const _StackedBars({
    required this.labels,
    required this.values,
    required this.greenLabel,
    required this.redLabel,
    this.scrollable = false,
  });
  final List<String> labels;
  final List<(int, int)> values;
  final String greenLabel;
  final String redLabel;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final maxCount = values.fold<int>(
      0,
      (max, value) => math.max(max, value.$1 + value.$2),
    );
    final interval = math.max(1, (maxCount / 4).ceil());
    final maxY = math
        .max(interval, (maxCount / interval).ceil() * interval)
        .toDouble();
    final textColor = Theme.of(context).colorScheme.onSurface;
    final barChart = BarChart(
      BarChartData(
        maxY: maxY,
        minY: 0,
        alignment: BarChartAlignment.spaceAround,
        barGroups: [
          for (var index = 0; index < values.length; index++)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: (values[index].$1 + values[index].$2).toDouble(),
                  width: scrollable ? 20 : 28,
                  borderRadius: BorderRadius.zero,
                  rodStackItems: [
                    if (values[index].$1 > 0)
                      BarChartRodStackItem(
                        0,
                        values[index].$1.toDouble(),
                        _green,
                      ),
                    if (values[index].$2 > 0)
                      BarChartRodStackItem(
                        values[index].$1.toDouble(),
                        (values[index].$1 + values[index].$2).toDouble(),
                        _red,
                      ),
                  ],
                ),
              ],
            ),
        ],
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            fitInsideVertically: true,
            getTooltipColor: (_) =>
                Theme.of(context).colorScheme.surfaceContainerHighest,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              final value = values[group.x];
              return BarTooltipItem(
                '${labels[group.x]}\n$greenLabel: ${value.$1}\n$redLabel: ${value.$2}',
                TextStyle(color: textColor),
              );
            },
          ),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval.toDouble(),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 42,
              interval: interval.toDouble(),
              getTitlesWidget: (value, meta) => Text(
                value.toInt().toString(),
                style: TextStyle(color: textColor, fontSize: 11),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= labels.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    labels[index],
                    style: TextStyle(color: textColor, fontSize: 12),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      duration: Duration.zero,
    );
    if (!scrollable) return SizedBox(height: 230, child: barChart);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: math.max(constraints.maxWidth, 42.0 + labels.length * 36.0),
          height: 230,
          child: barChart,
        ),
      ),
    );
  }
}
