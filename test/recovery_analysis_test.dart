import 'package:flutter_test/flutter_test.dart';
import 'package:solesync/models/insole_record.dart';
import 'package:solesync/models/record_summary.dart';
import 'package:solesync/services/clinical_gait_analysis.dart';
import 'package:solesync/services/recovery_analysis.dart';

RecordSummary _summary(double rightLoadPercent) => RecordSummary(
      stepCount: 0,
      cadenceSpm: 0,
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
      rightLoadPercent: rightLoadPercent,
    );

InsoleRecord _record(int id, String date, double rightLoadPercent) => InsoleRecord(
      id: id,
      name: 'Insole',
      date: date,
      time: 60,
      summary: _summary(rightLoadPercent),
      framesFilePath: null,
      distanceKm: 0,
      pace: 0,
      totalTime: 1,
      path: const [],
    );

void main() {
  group('RecoveryAnalysis', () {
    test('reports insufficientData with fewer than 2 sessions', () {
      final result = RecoveryAnalysis.compare(records: [_record(1, '2024-01-01 09:00', 60)]);
      expect(result.trend, RecoveryTrend.insufficientData);
    });

    test('detects an improving trend toward balance', () {
      final records = [
        _record(1, '2024-01-01 09:00', 70), // right-dominant early on
        _record(2, '2024-01-03 09:00', 68),
        _record(3, '2024-01-20 09:00', 52), // much closer to balanced now
        _record(4, '2024-01-22 09:00', 51),
      ];
      final result = RecoveryAnalysis.compare(records: records, windowSize: 2);
      expect(result.trend, RecoveryTrend.improving);
      expect(result.earlyRightLoadPercent, closeTo(69, 0.01));
      expect(result.recentRightLoadPercent, closeTo(51.5, 0.01));
      expect(result.summary, contains('Improving'));
    });

    test('detects a worsening trend away from balance', () {
      final records = [
        _record(1, '2024-01-01 09:00', 52),
        _record(2, '2024-01-03 09:00', 51),
        _record(3, '2024-01-20 09:00', 72),
        _record(4, '2024-01-22 09:00', 74),
      ];
      final result = RecoveryAnalysis.compare(records: records, windowSize: 2);
      expect(result.trend, RecoveryTrend.worsening);
      expect(result.summary, contains('Worth flagging'));
    });

    test('reports steady when the change is within noise', () {
      final records = [
        _record(1, '2024-01-01 09:00', 54),
        _record(2, '2024-01-03 09:00', 55),
        _record(3, '2024-01-20 09:00', 53),
        _record(4, '2024-01-22 09:00', 56),
      ];
      final result = RecoveryAnalysis.compare(records: records, windowSize: 2);
      expect(result.trend, RecoveryTrend.steady);
    });

    test('ignores sessions before the recovery milestone date', () {
      final records = [
        _record(1, '2023-12-01 09:00', 95), // pre-surgery, wildly asymmetric -- irrelevant
        _record(2, '2024-01-02 09:00', 70),
        _record(3, '2024-01-03 09:00', 68),
        _record(4, '2024-01-20 09:00', 52),
        _record(5, '2024-01-22 09:00', 51),
      ];
      final result = RecoveryAnalysis.compare(
        records: records,
        milestoneDate: DateTime(2024, 1, 1),
        windowSize: 2,
      );
      expect(result.earlyRightLoadPercent, closeTo(69, 0.01));
      expect(result.trend, RecoveryTrend.improving);
    });

    test('does not crash and halves the window when early/recent would overlap', () {
      final records = [
        _record(1, '2024-01-01 09:00', 70),
        _record(2, '2024-01-02 09:00', 60),
        _record(3, '2024-01-03 09:00', 50),
      ];
      final result = RecoveryAnalysis.compare(records: records, windowSize: 5);
      expect(result.earlySessionCount + result.recentSessionCount, lessThanOrEqualTo(3));
      expect(result.trend, isNot(RecoveryTrend.insufficientData));
    });

    test('attaches no condition context when condition is other (default)', () {
      final records = [
        _record(1, '2024-01-01 09:00', 70),
        _record(2, '2024-01-20 09:00', 52),
      ];
      final result = RecoveryAnalysis.compare(records: records, windowSize: 2);
      expect(result.conditionContext, isNull);
    });

    test('attaches ACL-literature context for a knee condition', () {
      final records = [
        _record(1, '2024-01-01 09:00', 70),
        _record(2, '2024-01-20 09:00', 52),
      ];
      final result = RecoveryAnalysis.compare(
        records: records,
        condition: RecoveryCondition.knee,
        windowSize: 2,
      );
      expect(result.conditionContext, isNotNull);
      expect(result.conditionContext, contains('ACL-reconstruction'));
    });

    test('attaches stroke-literature context for a stroke condition', () {
      final records = [
        _record(1, '2024-01-01 09:00', 70),
        _record(2, '2024-01-20 09:00', 52),
      ];
      final result = RecoveryAnalysis.compare(
        records: records,
        condition: RecoveryCondition.strokeHemiparetic,
        windowSize: 2,
      );
      expect(result.conditionContext, isNotNull);
      expect(result.conditionContext, contains('paretic'));
    });

    test('knee context notes early stage when well within 3 months of milestone', () {
      // Record dates must fall after milestoneDate for the comparison to
      // include them at all, so these are relative to now rather than
      // fixed, unlike the other tests above.
      String fmt(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} 09:00';
      final now = DateTime.now();
      final records = [
        _record(1, fmt(now.subtract(const Duration(days: 8))), 70),
        _record(2, fmt(now.subtract(const Duration(days: 3))), 65),
      ];
      final result = RecoveryAnalysis.compare(
        records: records,
        milestoneDate: now.subtract(const Duration(days: 10)),
        condition: RecoveryCondition.knee,
        windowSize: 2,
      );
      expect(result.conditionContext, contains('early stage'));
    });
  });
}
