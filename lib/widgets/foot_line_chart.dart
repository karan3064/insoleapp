import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../models/foot_line_data.dart';
import '../theme/app_colors.dart';

/// 16-series pressure-over-time line chart, mirroring
/// `components/insole/line/line.vue` (live, last-10-points) and
/// `components/insole/LineShow/LineShow.vue` (full replay).
class FootLineChart extends StatelessWidget {
  final FootLineData data;
  final int? windowSize; // null = show everything
  final double height;

  const FootLineChart({
    super.key,
    required this.data,
    this.windowSize = 10,
    this.height = 180,
  });

  static const _palette = [
    Color(0xFF2DD4BF), Color(0xFF60A5FA), Color(0xFFFBBF24), Color(0xFFF87171),
    Color(0xFFA78BFA), Color(0xFF34D399), Color(0xFFF472B6), Color(0xFF38BDF8),
    Color(0xFFFACC15), Color(0xFFFB923C), Color(0xFF4ADE80), Color(0xFFC084FC),
    Color(0xFF22D3EE), Color(0xFFE879F9), Color(0xFF818CF8), Color(0xFFF97316),
  ];

  @override
  Widget build(BuildContext context) {
    final series = <List<FlSpot>>[];
    var maxLen = 0;

    for (var s = 0; s < data.series.length; s++) {
      var values = data.series[s];
      if (windowSize != null && values.length > windowSize!) {
        values = values.sublist(values.length - windowSize!);
      }
      maxLen = values.length > maxLen ? values.length : maxLen;
      series.add([
        for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i].toDouble()),
      ]);
    }

    if (maxLen == 0) {
      return SizedBox(
        height: height,
        child: const Center(
          child: Text('No data yet', style: TextStyle(color: AppColors.textTertiary)),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (maxLen - 1).toDouble().clamp(1, double.infinity),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: AppColors.border, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) => Text(
                  value.toInt().toString(),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                ),
              ),
            ),
          ),
          lineBarsData: [
            for (var s = 0; s < series.length; s++)
              LineChartBarData(
                spots: series[s],
                isCurved: true,
                color: _palette[s % _palette.length],
                barWidth: 2,
                dotData: const FlDotData(show: false),
              ),
          ],
        ),
      ),
    );
  }
}
