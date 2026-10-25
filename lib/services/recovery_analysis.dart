import '../models/insole_record.dart';

/// Which foot a load trend is improving toward balance for, or away from
/// it, or holding steady -- what a physiotherapist tracking post-surgery
/// weight-bearing actually wants to see across sessions, not any single
/// session's raw numbers.
enum RecoveryTrend { improving, worsening, steady, insufficientData }

class RecoveryComparison {
  /// Average right-foot load % (50 = balanced) over the earliest
  /// available sessions -- the "before" baseline.
  final double? earlyRightLoadPercent;

  /// Average right-foot load % over the most recent sessions -- the
  /// "now" comparison point.
  final double? recentRightLoadPercent;

  final int earlySessionCount;
  final int recentSessionCount;
  final RecoveryTrend trend;
  final String summary;

  const RecoveryComparison({
    required this.earlyRightLoadPercent,
    required this.recentRightLoadPercent,
    required this.earlySessionCount,
    required this.recentSessionCount,
    required this.trend,
    required this.summary,
  });
}

/// Compares a patient's weight-bearing distribution (which foot carries
/// more load, from `RecordSummary.rightLoadPercent`) between an early
/// baseline and their most recent sessions, and writes the result as a
/// plain-language sentence a physiotherapist or patient can read directly
/// -- raw FSR pressure values and heatmaps mean nothing to a clinician on
/// their own; this is the translation layer.
///
/// Deliberately doesn't need any external dataset or trained model: this
/// is a within-patient, relative comparison (are THEY more balanced than
/// THEY used to be), which is a far more reliable question to answer from
/// this app's own hardware than any cross-population classification would
/// be.
class RecoveryAnalysis {
  RecoveryAnalysis._();

  /// Sessions within this many points of 50 (perfectly balanced) count as
  /// "balanced" for the summary wording -- avoids reading normal day-to-day
  /// noise as a meaningful side preference.
  static const _balancedBandPoints = 3.0;

  /// A day-to-day change smaller than this isn't called out as a real
  /// trend -- it's within the kind of session-to-session noise any gait
  /// metric has.
  static const _meaningfulChangePoints = 4.0;

  /// [records] need not be pre-sorted. [milestoneDate], if given, anchors
  /// the "early" baseline to the sessions shortly after it (e.g. right
  /// after a surgery date) instead of just the patient's very first-ever
  /// sessions, which may predate the condition being tracked entirely.
  /// [windowSize] caps how many sessions go into each side of the
  /// comparison, so one side isn't just diluted by a much larger history.
  static RecoveryComparison compare({
    required List<InsoleRecord> records,
    DateTime? milestoneDate,
    int windowSize = 5,
  }) {
    final sorted = [...records]..sort((a, b) => a.date.compareTo(b.date));

    final afterMilestone = milestoneDate == null
        ? sorted
        : sorted.where((r) => _parseDate(r.date)?.isAfter(milestoneDate) ?? true).toList();

    if (afterMilestone.length < 2) {
      return const RecoveryComparison(
        earlyRightLoadPercent: null,
        recentRightLoadPercent: null,
        earlySessionCount: 0,
        recentSessionCount: 0,
        trend: RecoveryTrend.insufficientData,
        summary: 'Not enough sessions yet to show a recovery trend -- at least a '
            'couple of sessions are needed, ideally spread across different days.',
      );
    }

    final earlyWindow = afterMilestone.take(windowSize).toList();
    final recentWindow = afterMilestone.reversed.take(windowSize).toList();

    // Guard against a short history where the two windows would overlap
    // and compare a period to itself.
    final overlap = earlyWindow.length + recentWindow.length > afterMilestone.length;
    final effectiveRecent = overlap
        ? afterMilestone.skip(afterMilestone.length ~/ 2).toList()
        : recentWindow;
    final effectiveEarly = overlap
        ? afterMilestone.take(afterMilestone.length - effectiveRecent.length).toList()
        : earlyWindow;

    final early = _meanRightLoad(effectiveEarly);
    final recent = _meanRightLoad(effectiveRecent);

    final delta = recent - early; // positive = shifted toward right foot
    final earlyDistanceFromBalance = (early - 50).abs();
    final recentDistanceFromBalance = (recent - 50).abs();
    final improvement = earlyDistanceFromBalance - recentDistanceFromBalance;

    final RecoveryTrend trend;
    if (improvement.abs() < _meaningfulChangePoints) {
      trend = RecoveryTrend.steady;
    } else if (improvement > 0) {
      trend = RecoveryTrend.improving;
    } else {
      trend = RecoveryTrend.worsening;
    }

    return RecoveryComparison(
      earlyRightLoadPercent: early,
      recentRightLoadPercent: recent,
      earlySessionCount: effectiveEarly.length,
      recentSessionCount: effectiveRecent.length,
      trend: trend,
      summary: _narrative(
        early: early,
        recent: recent,
        delta: delta,
        trend: trend,
        earlyDistanceFromBalance: earlyDistanceFromBalance,
        recentDistanceFromBalance: recentDistanceFromBalance,
      ),
    );
  }

  static double _meanRightLoad(List<InsoleRecord> records) {
    if (records.isEmpty) return 50;
    final sum = records.fold<double>(0, (s, r) => s + r.summary.rightLoadPercent);
    return sum / records.length;
  }

  static String _sideName(double rightLoadPercent) =>
      rightLoadPercent > 50 ? 'right' : 'left';

  static String _narrative({
    required double early,
    required double recent,
    required double delta,
    required RecoveryTrend trend,
    required double earlyDistanceFromBalance,
    required double recentDistanceFromBalance,
  }) {
    final recentSide = _sideName(recent);
    final recentPct = (50 + recentDistanceFromBalance).toStringAsFixed(0);
    final isNowBalanced = recentDistanceFromBalance < _balancedBandPoints;

    final currentState = isNowBalanced
        ? 'Weight-bearing is now close to balanced between both feet.'
        : 'The $recentSide foot is currently carrying about $recentPct% of the load.';

    switch (trend) {
      case RecoveryTrend.improving:
        final earlySide = _sideName(early);
        final earlyPct = (50 + earlyDistanceFromBalance).toStringAsFixed(0);
        return 'Improving: weight-bearing has shifted toward balance -- the $earlySide '
            'foot carried about $earlyPct% of the load in earlier sessions, versus '
            '$recentPct% now. $currentState';
      case RecoveryTrend.worsening:
        return 'Worth flagging: weight-bearing asymmetry has increased since earlier '
            'sessions, not decreased. $currentState Consider reviewing with the '
            'treating clinician.';
      case RecoveryTrend.steady:
        return isNowBalanced
            ? 'Steady and balanced across sessions -- no meaningful left/right shift detected.'
            : '$currentState This hasn\'t changed meaningfully across sessions so far.';
      case RecoveryTrend.insufficientData:
        return 'Not enough sessions yet to show a recovery trend.';
    }
  }

  static DateTime? _parseDate(String date) {
    // Record dates are "YYYY-MM-DD HH:mm"; DateTime.tryParse handles the
    // space-separated form directly.
    return DateTime.tryParse(date);
  }
}
