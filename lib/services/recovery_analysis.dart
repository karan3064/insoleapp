import '../models/insole_record.dart';

/// Which foot a load trend is improving toward balance for, or away from
/// it, or holding steady -- what a physiotherapist tracking post-surgery
/// weight-bearing actually wants to see across sessions, not any single
/// session's raw numbers.
enum RecoveryTrend { improving, worsening, steady, insufficientData }

/// The condition a recovery milestone is tracking -- lets [RecoveryAnalysis]
/// attach literature-sourced context specific to that condition (see
/// [RecoveryAnalysis._conditionContext]) rather than only a generic trend.
/// Each one is backed by a real, cited source; a condition with no
/// well-established quantitative reference gets no context attached rather
/// than a made-up one.
enum RecoveryCondition { knee, strokeHemiparetic, other }

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

  /// Literature-sourced context for the patient's condition (e.g. a
  /// typical ACL-reconstruction recovery timeline), or null when
  /// [RecoveryCondition.other] is set or no well-established quantitative
  /// reference exists for the condition. Always cited -- see
  /// [RecoveryAnalysis._conditionContext].
  final String? conditionContext;

  const RecoveryComparison({
    required this.earlyRightLoadPercent,
    required this.recentRightLoadPercent,
    required this.earlySessionCount,
    required this.recentSessionCount,
    required this.trend,
    required this.summary,
    this.conditionContext,
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
    RecoveryCondition condition = RecoveryCondition.other,
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
      conditionContext: _conditionContext(condition: condition, milestoneDate: milestoneDate),
    );
  }

  /// Literature-sourced context for the patient's tracked condition. Each
  /// branch cites a real published source rather than an invented
  /// threshold -- see the comments below for exactly what's claimed and
  /// where it comes from.
  static String? _conditionContext({
    required RecoveryCondition condition,
    required DateTime? milestoneDate,
  }) {
    switch (condition) {
      case RecoveryCondition.knee:
        // A longitudinal study of 20 unilateral ACL-reconstruction
        // patients (3-24 months post-op) found vertical-ground-reaction-
        // force symmetry abnormal at 3 months, mostly normalizing by
        // 6-12 months, while knee-extension-moment asymmetry could
        // persist past 24 months. Source: "Progressive alterations in
        // gait biomechanical symmetry within 2 years after ACL
        // reconstruction" (pure.bit.edu.cn). This is population-level
        // literature context, not a prediction for this specific
        // patient.
        final monthsSince = milestoneDate == null
            ? null
            : DateTime.now().difference(milestoneDate).inDays / 30.44;
        final stageNote = monthsSince == null
            ? ''
            : monthsSince < 3
                ? ' At this early stage (under 3 months), some weight-bearing asymmetry is expected.'
                : monthsSince < 6
                    ? ' Published ACL-reconstruction research found load symmetry still abnormal around this '
                        'stage (3 months) in most patients, typically normalizing by 6-12 months.'
                    : monthsSince < 12
                        ? ' Most patients in published ACL-reconstruction research had load symmetry normalize '
                            'by this stage (6-12 months) -- if asymmetry is still substantial, it may be worth '
                            'flagging to the clinician.'
                        : ' Published research found load/force symmetry typically normalizes well before this '
                            'stage (12+ months), though some asymmetry (e.g. in knee-extension force) can '
                            'persist past 2 years in a minority of patients.';
        return 'Context from published ACL-reconstruction research: weight-bearing asymmetry is common '
            'and expected in the first few months, typically improving over 6-12 months.$stageNote';

      case RecoveryCondition.strokeHemiparetic:
        // Van Criekinge et al., 2023 (Scientific Data) -- a real published
        // cohort of 50 stroke survivors with clinical mobility scores
        // (Functional Ambulation Category, Tinetti POMA, Trunk Impairment
        // Scale). Deliberately NOT quoting precise summary statistics
        // computed from that cohort here -- hand-transcribing many values
        // off a table risks a wrong number stated with false confidence,
        // and it's not needed to make the one well-established clinical
        // point below.
        return 'Context from published stroke-gait research: temporal/speed symmetry between the paretic '
            'and non-paretic side can look better than the underlying asymmetry in loading or muscle '
            'activity actually is -- many stroke survivors compensate to achieve similar step timing on '
            'both sides even when the affected side bears meaningfully less load. Treat a balanced-looking '
            'trend here as encouraging but not conclusive on its own; a clinician\'s assessment (e.g. '
            'Functional Ambulation Category, Tinetti POMA) captures more than weight-bearing alone.';

      case RecoveryCondition.other:
        return null;
    }
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
