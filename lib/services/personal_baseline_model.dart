import 'dart:math';

import '../models/insole_record.dart';

/// How far this session's tracked metrics sit from this specific patient's
/// own historical normal range.
enum PersonalAnomalyLevel { normal, mild, significant, insufficientData }

/// One tracked metric's deviation from this patient's own baseline for that
/// metric.
class MetricDeviation {
  final String metricKey;
  final String displayLabel;
  final double value;
  final double baselineMean;
  final double baselineSd;
  final double zScore;

  const MetricDeviation({
    required this.metricKey,
    required this.displayLabel,
    required this.value,
    required this.baselineMean,
    required this.baselineSd,
    required this.zScore,
  });
}

class PersonalBaselineResult {
  final PersonalAnomalyLevel level;
  final int baselineSessionCount;
  final String summary;

  /// Only metrics with enough baseline history to score, worst (largest
  /// |z-score|) first. Empty when [level] is [PersonalAnomalyLevel.insufficientData].
  final List<MetricDeviation> deviations;

  const PersonalBaselineResult({
    required this.level,
    required this.baselineSessionCount,
    required this.summary,
    required this.deviations,
  });
}

/// Flags how unusual a session is *for this specific patient*, rather than
/// against any external population.
///
/// `GaitScreeningModel` is trained on an external dataset (PhysioNet
/// PD-vs-control recordings) -- useful as a one-off population-level
/// screen, but it will never fit this app's own hardware or any specific
/// patient's own normal gait as well as that patient's own history does.
/// This model needs no external dataset at all: it learns a baseline
/// (per-metric mean/standard-deviation) purely from a patient's own past
/// sessions -- data this app already computes and stores in every
/// [RecordSummary] -- and scores each new session against THEIR OWN
/// distribution, not anyone else's.
///
/// Honest limitation: this has a cold start. Until a patient has logged
/// [minBaselineSessions] sessions, there's no meaningful baseline yet to
/// compare against, so [PersonalAnomalyLevel.insufficientData] is returned
/// instead of guessing from too little history.
class PersonalBaselineModel {
  PersonalBaselineModel._();

  /// Minimum past sessions (for a given metric) required before that
  /// metric is scored at all.
  static const minBaselineSessions = 5;

  /// |z-score| thresholds, same convention as standard-deviation-based
  /// outlier screening (~95th / ~99.7th percentile of a normal
  /// distribution).
  static const _mildZ = 2.0;
  static const _significantZ = 3.0;

  /// [history] need not include [current] or be pre-sorted; need not be
  /// pre-filtered either -- [current] is excluded from its own baseline by
  /// id.
  static PersonalBaselineResult evaluate({
    required List<InsoleRecord> history,
    required InsoleRecord current,
  }) {
    final past = history.where((r) => r.id != current.id).toList();

    final currentMetrics = _extractMetrics(current);
    final deviations = <MetricDeviation>[];

    for (final key in currentMetrics.keys) {
      final currentValue = currentMetrics[key];
      if (currentValue == null) continue;

      final baselineValues = past
          .map((r) => _extractMetrics(r)[key])
          .whereType<double>()
          .toList();
      if (baselineValues.length < minBaselineSessions) continue;

      final mean = _mean(baselineValues);
      final sd = _stdDev(baselineValues, mean);
      if (sd == 0) continue; // no recorded variability -> can't score this patient on this metric yet

      deviations.add(MetricDeviation(
        metricKey: key,
        displayLabel: _displayLabel(key),
        value: currentValue,
        baselineMean: mean,
        baselineSd: sd,
        zScore: (currentValue - mean) / sd,
      ));
    }

    if (deviations.isEmpty) {
      return PersonalBaselineResult(
        level: PersonalAnomalyLevel.insufficientData,
        baselineSessionCount: past.length,
        summary: 'Still learning your personal baseline -- ${past.length} of '
            '$minBaselineSessions sessions logged so far. Keep logging sessions to '
            'unlock personalized deviation alerts for this patient.',
        deviations: const [],
      );
    }

    deviations.sort((a, b) => b.zScore.abs().compareTo(a.zScore.abs()));
    final worst = deviations.first;
    final level = worst.zScore.abs() >= _significantZ
        ? PersonalAnomalyLevel.significant
        : worst.zScore.abs() >= _mildZ
            ? PersonalAnomalyLevel.mild
            : PersonalAnomalyLevel.normal;

    return PersonalBaselineResult(
      level: level,
      baselineSessionCount: past.length,
      summary: _narrative(level: level, worst: worst),
      deviations: deviations,
    );
  }

  static Map<String, double?> _extractMetrics(InsoleRecord r) {
    final s = r.summary;
    final cv = [s.clinical.left.strideTimeCvPercent, s.clinical.right.strideTimeCvPercent]
        .whereType<double>()
        .toList();
    return {
      'cadence': s.cadenceSpm.toDouble(),
      'rightLoadPercent': s.rightLoadPercent,
      'strideTimeAsymmetryPercent': s.clinical.strideTimeAsymmetryPercent,
      'strideTimeCvPercent': cv.isEmpty ? null : cv.reduce((a, b) => a + b) / cv.length,
    };
  }

  static String _displayLabel(String key) {
    switch (key) {
      case 'cadence':
        return 'cadence';
      case 'rightLoadPercent':
        return 'left/right weight-bearing balance';
      case 'strideTimeAsymmetryPercent':
        return 'left/right stride-time asymmetry';
      case 'strideTimeCvPercent':
        return 'stride-time consistency';
      default:
        return key;
    }
  }

  static double _mean(List<double> values) => values.reduce((a, b) => a + b) / values.length;

  static double _stdDev(List<double> values, double mean) {
    final variance = values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) / values.length;
    return sqrt(variance);
  }

  static String _narrative({required PersonalAnomalyLevel level, required MetricDeviation worst}) {
    final direction = worst.zScore > 0 ? 'higher' : 'lower';
    final magnitude = worst.zScore.abs().toStringAsFixed(1);
    switch (level) {
      case PersonalAnomalyLevel.significant:
        return 'Significant deviation from your personal baseline: ${worst.displayLabel} this session is '
            'notably $direction than your typical range ($magnitude SD from your own average). Worth a '
            'closer look.';
      case PersonalAnomalyLevel.mild:
        return 'Mild deviation from your personal baseline: ${worst.displayLabel} is somewhat $direction '
            'than usual for you ($magnitude SD). Could be normal day-to-day variation -- worth watching '
            'over the next few sessions.';
      case PersonalAnomalyLevel.normal:
        return 'This session is within your normal personal range across tracked metrics.';
      case PersonalAnomalyLevel.insufficientData:
        return 'Still learning your personal baseline.';
    }
  }
}
