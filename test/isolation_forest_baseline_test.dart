import 'package:flutter_test/flutter_test.dart';
import 'package:solesync/models/insole_record.dart';
import 'package:solesync/models/record_summary.dart';
import 'package:solesync/services/clinical_gait_analysis.dart';
import 'package:solesync/services/isolation_forest_baseline.dart';

/// [strideCv] is split evenly across left/right so
/// `IsolationForestBaseline._extractVector`'s average-of-both-feet read
/// comes out to exactly this value.
InsoleRecord _record(
  int id,
  String date, {
  required double cadence,
  required double rightLoadPercent,
  required double asym,
  required double strideCv,
}) {
  return InsoleRecord(
    id: id,
    name: 'B2U-TEST',
    date: date,
    time: 60,
    summary: RecordSummary(
      stepCount: 0,
      cadenceSpm: cadence.round(),
      groundContactMs: 0,
      flightMs: 0,
      footprintLeft: '',
      footprintRight: '',
      archLeft: '',
      archRight: '',
      landingLeft: '',
      landingRight: '',
      forefootPct: 0,
      hindfootPct: 0,
      wholePct: 0,
      lFront: 0,
      rFront: 0,
      lMid: 0,
      rMid: 0,
      lRear: 0,
      rRear: 0,
      balancePercent: 0,
      clinical: ClinicalGaitReport(
        left: FootGaitMetrics(
            stepCount: 3, strideTimesMs: _seriesForCv(1100, strideCv), stanceTimesMs: const [], swingTimesMs: const []),
        right: FootGaitMetrics(
            stepCount: 3, strideTimesMs: _seriesForCv(1100, strideCv), stanceTimesMs: const [], swingTimesMs: const []),
        cadenceStepsPerMin: cadence,
        doubleSupportPercent: 30,
        singleSupportPercent: 70,
        strideTimeAsymmetryPercent: asym,
        stanceTimeAsymmetryPercent: 0,
      ),
      rightLoadPercent: rightLoadPercent,
    ),
    framesFilePath: null,
    distanceKm: 0,
    pace: 0,
    totalTime: 0,
    path: const [],
  );
}

/// Two points {m-d, m+d} with sample stdDev (n-1) giving exactly the
/// target CV% -- same reverse-engineering approach as the other model
/// test fixtures in this repo.
List<double> _seriesForCv(double meanVal, double cvPercent) {
  final sd = cvPercent / 100 * meanVal;
  final d = sd / 1.4142135623730951;
  return [meanVal - d, meanVal + d];
}

void main() {
  group('IsolationForestBaseline', () {
    test('insufficientData below minBaselineSessions', () {
      final history = [
        _record(1, '2026-01-01 08:00', cadence: 90, rightLoadPercent: 50, asym: 3, strideCv: 15),
        _record(2, '2026-01-02 08:00', cadence: 91, rightLoadPercent: 49, asym: 3.1, strideCv: 14.5),
      ];
      final current = _record(3, '2026-01-03 08:00', cadence: 90, rightLoadPercent: 50, asym: 3, strideCv: 15);
      final result = IsolationForestBaseline.evaluate(history: history, current: current, seed: 1);
      expect(result.level, IsolationAnomalyLevel.insufficientData);
    });

    test('a session far outside the baseline on every metric scores as more anomalous '
        'than one right in the middle of it', () {
      // Tight cluster: cadence~90, load~50, asym~3, strideCv~15, small jitter.
      final history = [
        _record(1, '2026-01-01 08:00', cadence: 89, rightLoadPercent: 49, asym: 2.8, strideCv: 14.5),
        _record(2, '2026-01-02 08:00', cadence: 91, rightLoadPercent: 51, asym: 3.2, strideCv: 15.5),
        _record(3, '2026-01-03 08:00', cadence: 90, rightLoadPercent: 50, asym: 3.0, strideCv: 15.0),
        _record(4, '2026-01-04 08:00', cadence: 88, rightLoadPercent: 48, asym: 2.9, strideCv: 14.8),
        _record(5, '2026-01-05 08:00', cadence: 92, rightLoadPercent: 52, asym: 3.1, strideCv: 15.2),
        _record(6, '2026-01-06 08:00', cadence: 90, rightLoadPercent: 50, asym: 3.0, strideCv: 15.0),
        _record(7, '2026-01-07 08:00', cadence: 89, rightLoadPercent: 51, asym: 2.9, strideCv: 14.9),
        _record(8, '2026-01-08 08:00', cadence: 91, rightLoadPercent: 49, asym: 3.1, strideCv: 15.1),
        _record(9, '2026-01-09 08:00', cadence: 90, rightLoadPercent: 50, asym: 3.0, strideCv: 15.0),
        _record(10, '2026-01-10 08:00', cadence: 90, rightLoadPercent: 50, asym: 3.0, strideCv: 15.0),
      ];

      final normalSession =
          _record(11, '2026-01-11 08:00', cadence: 90, rightLoadPercent: 50, asym: 3.0, strideCv: 15.0);
      final outlierSession =
          _record(12, '2026-01-12 08:00', cadence: 150, rightLoadPercent: 90, asym: 20, strideCv: 45);

      final normalResult = IsolationForestBaseline.evaluate(history: history, current: normalSession, seed: 7);
      final outlierResult = IsolationForestBaseline.evaluate(history: history, current: outlierSession, seed: 7);

      expect(normalResult.level, isNot(IsolationAnomalyLevel.insufficientData));
      expect(outlierResult.anomalyScore, greaterThan(normalResult.anomalyScore));
      expect(outlierResult.level, IsolationAnomalyLevel.significant);
      expect(normalResult.level, IsolationAnomalyLevel.normal);
    });
  });
}
