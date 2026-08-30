import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/insole_record.dart';
import '../services/gait_analysis.dart';
import '../state/insole_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/metric_card.dart';
import '../widgets/page_header.dart';

/// Mirrors `pages/trends/trends.vue`: last-7-days session count + step
/// count bar charts, plus a week-over-week trend summary.
class TrendsScreen extends StatelessWidget {
  const TrendsScreen({super.key});

  List<String> _lastNDays(int n, int offset) {
    final days = <String>[];
    for (var i = n - 1 + offset; i >= offset; i--) {
      final d = DateTime.now().subtract(Duration(days: i));
      days.add('${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}');
    }
    return days;
  }

  int _stepsFor(InsoleRecord record) => GaitAnalysis.processFrames(record.details);

  @override
  Widget build(BuildContext context) {
    final insole = context.watch<InsoleProvider>();
    final p = context.palette;

    final days = _lastNDays(7, 0);
    final previousDays = _lastNDays(7, 7);

    final sessionCounts = List.filled(7, 0);
    final stepCounts = List.filled(7, 0);
    var previousWeekSteps = 0;

    for (final record in insole.list) {
      final day = record.date.length >= 10 ? record.date.substring(0, 10) : '';
      final index = days.indexOf(day);
      if (index != -1) {
        sessionCounts[index]++;
        stepCounts[index] += _stepsFor(record);
        continue;
      }
      if (previousDays.contains(day)) {
        previousWeekSteps += _stepsFor(record);
      }
    }

    final totalSessions = sessionCounts.reduce((a, b) => a + b);
    final totalSteps = stepCounts.reduce((a, b) => a + b);
    final avgSteps = (totalSteps / 7).round();
    final trendPct = previousWeekSteps > 0
        ? ((totalSteps - previousWeekSteps) / previousWeekSteps * 100).round()
        : (totalSteps > 0 ? 100 : 0);

    final labels = days.map((d) => d.substring(5)).toList();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            const PageHeader(title: 'Trends'),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                      title: 'Total sessions', value: '$totalSessions', gradient: AppColors.gradActivity),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(title: 'Avg steps', value: '$avgSteps', gradient: AppColors.gradActivity),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    title: 'vs last week',
                    value: '${trendPct >= 0 ? '+' : ''}$trendPct%',
                    gradient: trendPct >= 0 ? AppColors.gradActivity : AppColors.gradBody,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _ChartCard(title: 'Sessions (7d)', values: sessionCounts, labels: labels, color: AppColors.primary),
            const SizedBox(height: 20),
            _ChartCard(
                title: 'Steps (7d)', values: stepCounts, labels: labels, color: p.textSecondary),
          ],
        ),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final List<int> values;
  final List<String> labels;
  final Color color;

  const _ChartCard({required this.title, required this.values, required this.labels, required this.color});

  @override
  Widget build(BuildContext context) {
    final maxV = values.isEmpty ? 1 : values.reduce((a, b) => a > b ? a : b);
    final p = context.palette;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: p.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: p.textSecondary)),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                maxY: (maxV == 0 ? 1 : maxV) * 1.2,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final i = value.toInt();
                        if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(labels[i], style: TextStyle(color: p.textSecondary, fontSize: 10)),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < values.length; i++)
                    BarChartGroupData(x: i, barRods: [
                      BarChartRodData(
                        toY: values[i].toDouble(),
                        color: color,
                        width: 18,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
