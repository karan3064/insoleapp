import 'dart:math';

import '../models/foot_line_data.dart';
import '../models/pressure_frame.dart';

/// One foot's stance phase: from heel-strike (pressure rises above the
/// contact threshold) to toe-off (pressure falls back below it), in
/// milliseconds since the session started.
class StanceInterval {
  final int heelStrikeMs;
  final int toeOffMs;

  const StanceInterval(this.heelStrikeMs, this.toeOffMs);

  int get durationMs => toeOffMs - heelStrikeMs;
}

/// Gait-cycle metrics for a single foot.
class FootGaitMetrics {
  final int stepCount;
  final List<double> strideTimesMs; // heel-strike to next heel-strike, same foot
  final List<double> stanceTimesMs; // heel-strike to toe-off
  final List<double> swingTimesMs; // toe-off to next heel-strike, same foot

  FootGaitMetrics({
    required this.stepCount,
    required this.strideTimesMs,
    required this.stanceTimesMs,
    required this.swingTimesMs,
  });

  double? get strideTimeMeanMs => ClinicalGaitAnalysis._mean(strideTimesMs);
  double? get strideTimeSdMs => ClinicalGaitAnalysis._stdDev(strideTimesMs);

  /// Stride-time coefficient of variation, as a percentage. Elevated
  /// stride-time CV is a widely-used gait-variability marker (e.g. in
  /// Parkinson's disease gait research) -- higher means less consistent
  /// timing between steps.
  double? get strideTimeCvPercent {
    final mean = strideTimeMeanMs;
    final sd = strideTimeSdMs;
    if (mean == null || mean == 0 || sd == null) return null;
    return sd / mean * 100;
  }

  double? get stanceTimeMeanMs => ClinicalGaitAnalysis._mean(stanceTimesMs);
  double? get swingTimeMeanMs => ClinicalGaitAnalysis._mean(swingTimesMs);

  /// Only the step count and stride/stance/swing time lists are kept --
  /// small (bounded by step count, not by session length) and enough to
  /// recompute every derived getter above without re-running detection.
  Map<String, dynamic> toJson() => {
        'stepCount': stepCount,
        'strideTimesMs': strideTimesMs,
        'stanceTimesMs': stanceTimesMs,
        'swingTimesMs': swingTimesMs,
      };

  factory FootGaitMetrics.fromJson(Map<String, dynamic> json) => FootGaitMetrics(
        stepCount: (json['stepCount'] as num).toInt(),
        strideTimesMs: (json['strideTimesMs'] as List).map((v) => (v as num).toDouble()).toList(),
        stanceTimesMs: (json['stanceTimesMs'] as List).map((v) => (v as num).toDouble()).toList(),
        swingTimesMs: (json['swingTimesMs'] as List).map((v) => (v as num).toDouble()).toList(),
      );
}

/// Full clinical gait-metrics report for one recorded session.
class ClinicalGaitReport {
  final FootGaitMetrics left;
  final FootGaitMetrics right;

  /// Total steps (both feet) per minute.
  final double? cadenceStepsPerMin;

  /// % of the recorded time both feet are in stance simultaneously.
  final double? doubleSupportPercent;

  /// % of the recorded time exactly one foot is in stance.
  final double? singleSupportPercent;

  /// Symmetry index between left/right mean stride time, as a percentage
  /// (0 = perfectly symmetric; higher = more asymmetric). Formula:
  /// |L - R| / (0.5*(L + R)) * 100.
  final double? strideTimeAsymmetryPercent;

  /// Same symmetry-index formula, applied to mean stance time.
  final double? stanceTimeAsymmetryPercent;

  ClinicalGaitReport({
    required this.left,
    required this.right,
    required this.cadenceStepsPerMin,
    required this.doubleSupportPercent,
    required this.singleSupportPercent,
    required this.strideTimeAsymmetryPercent,
    required this.stanceTimeAsymmetryPercent,
  });

  Map<String, dynamic> toJson() => {
        'left': left.toJson(),
        'right': right.toJson(),
        'cadenceStepsPerMin': cadenceStepsPerMin,
        'doubleSupportPercent': doubleSupportPercent,
        'singleSupportPercent': singleSupportPercent,
        'strideTimeAsymmetryPercent': strideTimeAsymmetryPercent,
        'stanceTimeAsymmetryPercent': stanceTimeAsymmetryPercent,
      };

  factory ClinicalGaitReport.fromJson(Map<String, dynamic> json) => ClinicalGaitReport(
        left: FootGaitMetrics.fromJson(Map<String, dynamic>.from(json['left'] as Map)),
        right: FootGaitMetrics.fromJson(Map<String, dynamic>.from(json['right'] as Map)),
        cadenceStepsPerMin: (json['cadenceStepsPerMin'] as num?)?.toDouble(),
        doubleSupportPercent: (json['doubleSupportPercent'] as num?)?.toDouble(),
        singleSupportPercent: (json['singleSupportPercent'] as num?)?.toDouble(),
        strideTimeAsymmetryPercent: (json['strideTimeAsymmetryPercent'] as num?)?.toDouble(),
        stanceTimeAsymmetryPercent: (json['stanceTimeAsymmetryPercent'] as num?)?.toDouble(),
      );

  /// A report with no detected steps -- used when there's no frame data
  /// to analyze (e.g. a record synced from another device with no local
  /// frame file available).
  static final empty = ClinicalGaitReport(
    left: FootGaitMetrics(stepCount: 0, strideTimesMs: [], stanceTimesMs: [], swingTimesMs: []),
    right: FootGaitMetrics(stepCount: 0, strideTimesMs: [], stanceTimesMs: [], swingTimesMs: []),
    cadenceStepsPerMin: null,
    doubleSupportPercent: null,
    singleSupportPercent: null,
    strideTimeAsymmetryPercent: null,
    stanceTimeAsymmetryPercent: null,
  );
}

/// Detects real gait events (heel-strike / toe-off) from the insole's
/// pressure signal and derives clinical gait-cycle metrics from them --
/// stride time & its variability, stance/swing time, double/single support,
/// left/right asymmetry, and cadence.
///
/// This replaces the crude "any nonzero frame counts as a step" proxy used
/// elsewhere in the app (`GaitAnalysis.processFrames`) with actual
/// event-based timing, which the stride-time/cadence/variability
/// calculations require to be meaningful.
///
/// These are raw, literature-standard gait measurements -- this class
/// makes no diagnostic claims or risk classifications; interpreting the
/// numbers clinically is left to the treating clinician.
class ClinicalGaitAnalysis {
  ClinicalGaitAnalysis._();

  /// Pressure sum (post threshold+scale, same units as the raw sensor
  /// grid) below which a sensor point is treated as "no contact". Matches
  /// the threshold already used by `GaitAnalysis.analyzeFlightAndContact`.
  static const contactThreshold = 10;

  static ClinicalGaitReport analyze({
    required FootLineData line,
    required FootLineData rightLine,
    required List<PressureFrame> details,
  }) {
    final leftSeries = _footPressureSeries(line, details);
    final rightSeries = _footPressureSeries(rightLine, details);

    final leftStances = _stanceIntervals(leftSeries);
    final rightStances = _stanceIntervals(rightSeries);

    final left = _footMetrics(leftStances);
    final right = _footMetrics(rightStances);

    final durationMs = _durationMs(details);

    final doubleSupportMs = _overlapMs(leftStances, rightStances);
    final leftStanceMs = leftStances.fold<int>(0, (sum, s) => sum + s.durationMs);
    final rightStanceMs = rightStances.fold<int>(0, (sum, s) => sum + s.durationMs);

    double? doubleSupportPercent;
    double? singleSupportPercent;
    if (durationMs > 0) {
      doubleSupportPercent = doubleSupportMs / durationMs * 100;
      final singleSupportMs = (leftStanceMs + rightStanceMs) - 2 * doubleSupportMs;
      singleSupportPercent = (singleSupportMs / durationMs * 100).clamp(0, 100).toDouble();
    }

    double? cadence;
    if (durationMs > 0) {
      final totalSteps = left.stepCount + right.stepCount;
      cadence = totalSteps / (durationMs / 60000);
    }

    return ClinicalGaitReport(
      left: left,
      right: right,
      cadenceStepsPerMin: cadence,
      doubleSupportPercent: doubleSupportPercent,
      singleSupportPercent: singleSupportPercent,
      strideTimeAsymmetryPercent:
          _symmetryIndex(left.strideTimeMeanMs, right.strideTimeMeanMs),
      stanceTimeAsymmetryPercent:
          _symmetryIndex(left.stanceTimeMeanMs, right.stanceTimeMeanMs),
    );
  }

  /// Per-frame total pressure (sum of all 16 sensor points) for one foot,
  /// paired with that frame's real timestamp (ms since session start).
  static List<MapEntry<int, int>> _footPressureSeries(
    FootLineData line,
    List<PressureFrame> frames,
  ) {
    final n = min(frames.length, line.series.isEmpty ? 0 : line.series[0].length);
    final result = <MapEntry<int, int>>[];
    for (var i = 0; i < n; i++) {
      var total = 0;
      for (final series in line.series) {
        total += series[i];
      }
      result.add(MapEntry(frames[i].time, total));
    }
    return result;
  }

  /// Rising-edge/falling-edge detection on a pressure-over-time series:
  /// a stance interval runs from the first sample above [contactThreshold]
  /// to the first sample back at or below it.
  static List<StanceInterval> _stanceIntervals(List<MapEntry<int, int>> series) {
    final intervals = <StanceInterval>[];
    int? startMs;

    for (final sample in series) {
      final inContact = sample.value > contactThreshold;
      if (inContact && startMs == null) {
        startMs = sample.key;
      } else if (!inContact && startMs != null) {
        intervals.add(StanceInterval(startMs, sample.key));
        startMs = null;
      }
    }

    // Trailing stance that never lifted off within the recording: close it
    // at the last sample rather than discarding the step entirely.
    if (startMs != null && series.isNotEmpty) {
      intervals.add(StanceInterval(startMs, series.last.key));
    }

    return intervals;
  }

  static FootGaitMetrics _footMetrics(List<StanceInterval> stances) {
    final strideTimes = <double>[];
    final swingTimes = <double>[];

    for (var i = 0; i < stances.length - 1; i++) {
      strideTimes.add((stances[i + 1].heelStrikeMs - stances[i].heelStrikeMs).toDouble());
      swingTimes.add((stances[i + 1].heelStrikeMs - stances[i].toeOffMs).toDouble());
    }

    return FootGaitMetrics(
      stepCount: stances.length,
      strideTimesMs: strideTimes,
      stanceTimesMs: stances.map((s) => s.durationMs.toDouble()).toList(),
      swingTimesMs: swingTimes,
    );
  }

  static int _durationMs(List<PressureFrame> frames) {
    if (frames.isEmpty) return 0;
    return frames.last.time - frames.first.time;
  }

  /// Total time (ms) both feet are simultaneously in stance.
  static int _overlapMs(List<StanceInterval> left, List<StanceInterval> right) {
    var overlap = 0;
    for (final l in left) {
      for (final r in right) {
        final start = max(l.heelStrikeMs, r.heelStrikeMs);
        final end = min(l.toeOffMs, r.toeOffMs);
        if (end > start) overlap += end - start;
      }
    }
    return overlap;
  }

  static double? _symmetryIndex(double? l, double? r) {
    if (l == null || r == null) return null;
    final avg = (l + r) / 2;
    if (avg == 0) return null;
    return (l - r).abs() / avg * 100;
  }

  static double? _mean(List<double> xs) {
    if (xs.isEmpty) return null;
    return xs.reduce((a, b) => a + b) / xs.length;
  }

  static double? _stdDev(List<double> xs) {
    if (xs.length < 2) return null;
    final mean = _mean(xs)!;
    final variance = xs.map((x) => (x - mean) * (x - mean)).reduce((a, b) => a + b) / (xs.length - 1);
    return sqrt(variance);
  }
}
