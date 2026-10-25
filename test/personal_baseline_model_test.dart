import 'package:flutter_test/flutter_test.dart';
import 'package:solesync/models/insole_record.dart';
import 'package:solesync/models/record_summary.dart';
import 'package:solesync/services/clinical_gait_analysis.dart';
import 'package:solesync/services/personal_baseline_model.dart';

InsoleRecord _record(int id, String date, int cadenceSpm) {
  return InsoleRecord(
    id: id,
    name: 'B2U-TEST',
    date: date,
    time: 60,
    summary: RecordSummary(
      stepCount: 0,
      cadenceSpm: cadenceSpm,
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
      clinical: ClinicalGaitReport.empty,
      rightLoadPercent: 50, // identical every session -> zero variance -> skipped as a metric
    ),
    framesFilePath: null,
    distanceKm: 0,
    pace: 0,
    totalTime: 0,
    path: const [],
  );
}

void main() {
  test('flags a significant personal-baseline deviation once enough history exists', () {
    // Baseline cadences 90/92/88/91/89 -> mean 90.0, sd sqrt(2) ≈ 1.41421356
    // (hand-verified independently before writing this test).
    final history = [
      _record(1, '2026-01-01 08:00', 90),
      _record(2, '2026-01-02 08:00', 92),
      _record(3, '2026-01-03 08:00', 88),
      _record(4, '2026-01-04 08:00', 91),
      _record(5, '2026-01-05 08:00', 89),
    ];
    final current = _record(6, '2026-01-06 08:00', 95);

    final result = PersonalBaselineModel.evaluate(history: history, current: current);

    expect(result.level, PersonalAnomalyLevel.significant);
    expect(result.baselineSessionCount, 5);
    expect(result.deviations, hasLength(1)); // rightLoadPercent has zero variance -> skipped
    final dev = result.deviations.single;
    expect(dev.metricKey, 'cadence');
    expect(dev.baselineMean, closeTo(90.0, 1e-9));
    expect(dev.baselineSd, closeTo(1.4142135623730951, 1e-9));
    expect(dev.zScore, closeTo(3.5355339059327373, 1e-9));
  });

  test('reports insufficientData before minBaselineSessions is reached', () {
    final history = [
      _record(1, '2026-01-01 08:00', 90),
      _record(2, '2026-01-02 08:00', 92),
    ];
    final current = _record(3, '2026-01-03 08:00', 95);

    final result = PersonalBaselineModel.evaluate(history: history, current: current);

    expect(result.level, PersonalAnomalyLevel.insufficientData);
    expect(result.baselineSessionCount, 2);
    expect(result.deviations, isEmpty);
  });

  test('a session within the personal normal range is not flagged', () {
    final history = [
      _record(1, '2026-01-01 08:00', 90),
      _record(2, '2026-01-02 08:00', 92),
      _record(3, '2026-01-03 08:00', 88),
      _record(4, '2026-01-04 08:00', 91),
      _record(5, '2026-01-05 08:00', 89),
    ];
    final current = _record(6, '2026-01-06 08:00', 90); // z = 0

    final result = PersonalBaselineModel.evaluate(history: history, current: current);

    expect(result.level, PersonalAnomalyLevel.normal);
  });
}
