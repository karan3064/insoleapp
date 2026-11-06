import 'dart:math';

import '../models/insole_record.dart';
import '../models/mood_entry.dart';

enum CorrelationStrength { insufficientData, weak, moderate, strong }

/// One metric's correlation with mood across paired days.
class MetricCorrelation {
  final String metricKey;
  final String displayLabel;
  final double r; // Pearson correlation coefficient, -1..1
  final CorrelationStrength strength;

  const MetricCorrelation({
    required this.metricKey,
    required this.displayLabel,
    required this.r,
    required this.strength,
  });
}

class MoodGaitCorrelationResult {
  final int pairedDays;
  final List<MetricCorrelation> correlations; // only metrics with enough data, strongest first
  final String summary;

  const MoodGaitCorrelationResult({
    required this.pairedDays,
    required this.correlations,
    required this.summary,
  });
}

/// Correlates a patient's daily mood check-ins (`MoodService`) against
/// their own measured gait metrics on the same day -- entirely within-
/// patient, like `RecoveryAnalysis` and `PersonalBaselineModel`, needing no
/// external dataset. Mood and gait quality are both real, independently
/// measured signals here; whether they move together for a given patient
/// is a genuine, previously-invisible insight, not a assumed correlation.
///
/// Honest limitation, same family as this app's other within-patient
/// models: correlation needs enough paired days to mean anything. Below
/// [minPairedDays], this returns [CorrelationStrength.insufficientData]
/// rather than reporting a correlation computed from too few points --
/// a Pearson r from 3 days is close to meaningless noise.
class MoodGaitCorrelation {
  MoodGaitCorrelation._();

  static const minPairedDays = 5;

  static MoodGaitCorrelationResult evaluate({
    required List<MoodEntry> moodEntries,
    required List<InsoleRecord> records,
  }) {
    final moodByDay = {for (final m in moodEntries) MoodEntry.dateKey(m.date): m.score.toDouble()};

    // Average same-day sessions together, so a day with multiple tests
    // doesn't get weighted more than a day with one.
    final metricSumsByDay = <String, Map<String, List<double>>>{};
    for (final r in records) {
      if (r.date.length < 10) continue;
      final dayKey = r.date.substring(0, 10);
      if (!moodByDay.containsKey(dayKey)) continue;
      final day = metricSumsByDay.putIfAbsent(dayKey, () => {'cadence': [], 'asym': []});
      day['cadence']!.add(r.summary.cadenceSpm.toDouble());
      final asym = r.summary.clinical.strideTimeAsymmetryPercent;
      if (asym != null) day['asym']!.add(asym);
    }

    final pairedDays = metricSumsByDay.length;
    if (pairedDays < minPairedDays) {
      return MoodGaitCorrelationResult(
        pairedDays: pairedDays,
        correlations: const [],
        summary: 'Still building a mood history -- $pairedDays of $minPairedDays days with both a '
            'mood check-in and a recorded session so far. Keep logging both to unlock this insight.',
      );
    }

    final correlations = <MetricCorrelation>[];
    _addIfAvailable(correlations, 'cadence', 'cadence', moodByDay, metricSumsByDay);
    _addIfAvailable(
        correlations, 'asym', 'left/right stride-time asymmetry', moodByDay, metricSumsByDay);

    if (correlations.isEmpty) {
      return MoodGaitCorrelationResult(
        pairedDays: pairedDays,
        correlations: const [],
        summary: 'Not enough variation in your recent mood or gait metrics yet to compute a '
            'meaningful correlation.',
      );
    }

    correlations.sort((a, b) => b.r.abs().compareTo(a.r.abs()));
    return MoodGaitCorrelationResult(
      pairedDays: pairedDays,
      correlations: correlations,
      summary: _narrative(correlations.first, pairedDays),
    );
  }

  static void _addIfAvailable(
    List<MetricCorrelation> out,
    String key,
    String label,
    Map<String, double> moodByDay,
    Map<String, Map<String, List<double>>> metricSumsByDay,
  ) {
    final xs = <double>[]; // mood
    final ys = <double>[]; // metric
    metricSumsByDay.forEach((day, metrics) {
      final values = metrics[key]!;
      if (values.isEmpty) return;
      xs.add(moodByDay[day]!);
      ys.add(values.reduce((a, b) => a + b) / values.length);
    });
    if (xs.length < minPairedDays) return;

    final r = _pearson(xs, ys);
    if (r == null) return;

    final CorrelationStrength strength;
    final absR = r.abs();
    if (absR >= 0.6) {
      strength = CorrelationStrength.strong;
    } else if (absR >= 0.3) {
      strength = CorrelationStrength.moderate;
    } else {
      strength = CorrelationStrength.weak;
    }
    out.add(MetricCorrelation(metricKey: key, displayLabel: label, r: r, strength: strength));
  }

  static double? _pearson(List<double> xs, List<double> ys) {
    final n = xs.length;
    final mx = xs.reduce((a, b) => a + b) / n;
    final my = ys.reduce((a, b) => a + b) / n;
    var cov = 0.0, vx = 0.0, vy = 0.0;
    for (var i = 0; i < n; i++) {
      final dx = xs[i] - mx;
      final dy = ys[i] - my;
      cov += dx * dy;
      vx += dx * dx;
      vy += dy * dy;
    }
    if (vx == 0 || vy == 0) return null;
    return cov / sqrt(vx * vy);
  }

  static String _narrative(MetricCorrelation top, int pairedDays) {
    if (top.strength == CorrelationStrength.weak) {
      return 'Across $pairedDays days with both a mood check-in and a recorded session, your mood '
          'and ${top.displayLabel} don\'t show a clear relationship yet.';
    }
    final direction = top.r > 0 ? 'higher' : 'lower';
    final strengthWord = top.strength == CorrelationStrength.strong ? 'A fairly consistent' : 'A noticeable';
    return '$strengthWord pattern across $pairedDays days: on days you report feeling better, your '
        '${top.displayLabel} tends to be $direction. This is a correlation in your own data, not '
        'a diagnosis or a causal claim -- worth mentioning to your clinician, not acting on alone.';
  }
}
