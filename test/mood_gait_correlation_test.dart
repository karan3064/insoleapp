import 'package:flutter_test/flutter_test.dart';
import 'package:solesync/models/insole_record.dart';
import 'package:solesync/models/mood_entry.dart';
import 'package:solesync/models/record_summary.dart';
import 'package:solesync/services/clinical_gait_analysis.dart';
import 'package:solesync/services/mood_gait_correlation.dart';

InsoleRecord _recordOn(int id, String dateKey, int cadenceSpm) {
  return InsoleRecord(
    id: id,
    name: 'B2U-TEST',
    date: '$dateKey 08:00',
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
      rightLoadPercent: 50,
    ),
    framesFilePath: null,
    distanceKm: 0,
    pace: 0,
    totalTime: 0,
    path: const [],
  );
}

MoodEntry _moodOn(String dateKey, int score) =>
    MoodEntry(id: dateKey, date: DateTime.parse(dateKey), score: score);

void main() {
  test('reports insufficientData below minPairedDays', () {
    final dates = ['2026-01-01', '2026-01-02', '2026-01-03'];
    final moods = [_moodOn(dates[0], 3), _moodOn(dates[1], 4), _moodOn(dates[2], 2)];
    final records = [
      for (var i = 0; i < dates.length; i++) _recordOn(i, dates[i], 90),
    ];
    final result = MoodGaitCorrelation.evaluate(moodEntries: moods, records: records);
    expect(result.pairedDays, 3);
    expect(result.correlations, isEmpty);
  });

  test('computes the exact Pearson correlation for cadence vs mood', () {
    // mood=[1,2,3,4,5,6], cadence=[100,95,110,90,120,80] -> r≈-0.1683395153249084
    // (independently verified in Python before writing this assertion).
    final dates = ['2026-01-01', '2026-01-02', '2026-01-03', '2026-01-04', '2026-01-05', '2026-01-06'];
    final moodScores = [1, 2, 3, 4, 5, 6];
    final cadences = [100, 95, 110, 90, 120, 80];

    final moods = [for (var i = 0; i < dates.length; i++) _moodOn(dates[i], moodScores[i])];
    final records = [for (var i = 0; i < dates.length; i++) _recordOn(i, dates[i], cadences[i])];

    final result = MoodGaitCorrelation.evaluate(moodEntries: moods, records: records);
    expect(result.pairedDays, 6);
    final cadenceCorrelation = result.correlations.firstWhere((c) => c.metricKey == 'cadence');
    expect(cadenceCorrelation.r, closeTo(-0.1683395153249084, 1e-9));
    expect(cadenceCorrelation.strength, CorrelationStrength.weak);
  });

  test('only pairs days present in both mood entries and records', () {
    // Only 3 of 6 mood-logged days have a matching session -> insufficientData.
    final moodDates = ['2026-01-01', '2026-01-02', '2026-01-03', '2026-01-04', '2026-01-05', '2026-01-06'];
    final moods = [for (var i = 0; i < moodDates.length; i++) _moodOn(moodDates[i], 3)];
    final records = [
      _recordOn(0, '2026-01-01', 90),
      _recordOn(1, '2026-01-02', 92),
      _recordOn(2, '2026-01-03', 88),
    ];
    final result = MoodGaitCorrelation.evaluate(moodEntries: moods, records: records);
    expect(result.pairedDays, 3);
  });
}
