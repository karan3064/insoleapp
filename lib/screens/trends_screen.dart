import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/insole_record.dart';
import '../services/recovery_analysis.dart';
import '../state/auth_provider.dart';
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

  int _stepsFor(InsoleRecord record) => record.summary.stepCount;

  @override
  Widget build(BuildContext context) {
    final insole = context.watch<InsoleProvider>();
    final auth = context.watch<AuthProvider>();
    final p = context.palette;

    final milestone = DateTime.tryParse(auth.profile.recoveryMilestoneDate ?? '');
    final recovery = RecoveryAnalysis.compare(records: insole.list, milestoneDate: milestone);

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
            if (recovery.trend != RecoveryTrend.insufficientData) ...[
              const SizedBox(height: 20),
              _RecoveryCard(
                recovery: recovery,
                milestoneLabel: auth.profile.recoveryMilestoneLabel,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Translates `RecoveryAnalysis`'s weight-bearing comparison into a card a
/// physiotherapist or patient can read directly -- the whole point being
/// that raw FSR pressure values and a heatmap mean nothing to a clinician
/// on their own; this says in plain language which foot carries more load
/// and whether that's gotten better or worse across sessions.
class _RecoveryCard extends StatelessWidget {
  final RecoveryComparison recovery;
  final String? milestoneLabel;

  const _RecoveryCard({required this.recovery, required this.milestoneLabel});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (icon, color) = switch (recovery.trend) {
      RecoveryTrend.improving => (Icons.trending_up, AppColors.success),
      RecoveryTrend.worsening => (Icons.trending_down, AppColors.warning),
      RecoveryTrend.steady => (Icons.trending_flat, p.textSecondary),
      RecoveryTrend.insufficientData => (Icons.info_outline, p.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: p.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  milestoneLabel != null ? 'Recovery progress since $milestoneLabel' : 'Weight-bearing trend',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(recovery.summary, style: TextStyle(color: p.text, fontSize: 13, height: 1.4)),
          if (recovery.earlyRightLoadPercent != null && recovery.recentRightLoadPercent != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _LoadStat(
                    label: 'Earlier (${recovery.earlySessionCount} sessions)',
                    rightLoadPercent: recovery.earlyRightLoadPercent!,
                  ),
                ),
                Icon(Icons.arrow_forward, color: p.textTertiary, size: 16),
                Expanded(
                  child: _LoadStat(
                    label: 'Recent (${recovery.recentSessionCount} sessions)',
                    rightLoadPercent: recovery.recentRightLoadPercent!,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LoadStat extends StatelessWidget {
  final String label;
  final double rightLoadPercent;
  const _LoadStat({required this.label, required this.rightLoadPercent});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final side = rightLoadPercent > 50 ? 'Right' : 'Left';
    final pct = (50 + (rightLoadPercent - 50).abs()).toStringAsFixed(0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(label, style: TextStyle(color: p.textSecondary, fontSize: 11), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text('$side $pct%', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ],
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
