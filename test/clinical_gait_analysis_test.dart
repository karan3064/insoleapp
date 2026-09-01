import 'package:flutter_test/flutter_test.dart';
import 'package:solesync/models/foot_line_data.dart';
import 'package:solesync/models/pressure_frame.dart';
import 'package:solesync/services/clinical_gait_analysis.dart';

/// Builds a foot's 16-series pressure data from a list of (time, pressure)
/// samples, putting the whole value in series 0 and zero elsewhere --
/// ClinicalGaitAnalysis only cares about the per-frame sum.
FootLineData _footLine(List<int> pressures) {
  final line = FootLineData();
  for (final p in pressures) {
    line.push([p, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
  }
  return line;
}

bool _inAny(int t, List<List<int>> windows) =>
    windows.any((w) => t >= w[0] && t < w[1]);

void main() {
  group('ClinicalGaitAnalysis', () {
    // Synthetic 2-second walk sampled every 50ms (41 samples, t=0..2000).
    // Left heel-strikes at 0, 700, 1400ms; stance duration 300ms each.
    // Right heel-strikes at 250, 950, 1650ms; stance duration 300ms each.
    // -> stride time 700ms for both feet (perfectly symmetric, by design).
    // -> each stance pair overlaps the other foot's by exactly 50ms, so
    //    double support = 3 * 50ms = 150ms out of the 2000ms span.
    const leftWindows = [
      [0, 300],
      [700, 1000],
      [1400, 1700],
    ];
    const rightWindows = [
      [250, 550],
      [950, 1250],
      [1650, 1950],
    ];

    late List<PressureFrame> details;
    late FootLineData line;
    late FootLineData rightLine;

    setUp(() {
      final times = List.generate(41, (i) => i * 50); // 0,50,...,2000
      final leftPressures = times.map((t) => _inAny(t, leftWindows) ? 100 : 0).toList();
      final rightPressures = times.map((t) => _inAny(t, rightWindows) ? 100 : 0).toList();

      details = [
        for (var i = 0; i < times.length; i++) PressureFrame(time: times[i], item: emptyGrid()),
      ];
      line = _footLine(leftPressures);
      rightLine = _footLine(rightPressures);
    });

    test('detects the correct step count per foot', () {
      final report = ClinicalGaitAnalysis.analyze(line: line, rightLine: rightLine, details: details);
      expect(report.left.stepCount, 3);
      expect(report.right.stepCount, 3);
    });

    test('computes stride time mean and zero variability for a perfectly regular gait', () {
      final report = ClinicalGaitAnalysis.analyze(line: line, rightLine: rightLine, details: details);
      expect(report.left.strideTimeMeanMs, 700);
      expect(report.right.strideTimeMeanMs, 700);
      expect(report.left.strideTimeCvPercent, 0);
      expect(report.right.strideTimeCvPercent, 0);
    });

    test('computes stance time mean per foot', () {
      final report = ClinicalGaitAnalysis.analyze(line: line, rightLine: rightLine, details: details);
      expect(report.left.stanceTimeMeanMs, 300);
      expect(report.right.stanceTimeMeanMs, 300);
    });

    test('computes cadence as total steps per minute', () {
      final report = ClinicalGaitAnalysis.analyze(line: line, rightLine: rightLine, details: details);
      // 6 total steps over a 2000ms (1/30 min) span = 180 steps/min.
      expect(report.cadenceStepsPerMin, closeTo(180, 0.001));
    });

    test('computes double-support and single-support percentages', () {
      final report = ClinicalGaitAnalysis.analyze(line: line, rightLine: rightLine, details: details);
      expect(report.doubleSupportPercent, closeTo(7.5, 0.001));
      expect(report.singleSupportPercent, closeTo(75, 0.001));
    });

    test('reports zero asymmetry for a symmetric gait', () {
      final report = ClinicalGaitAnalysis.analyze(line: line, rightLine: rightLine, details: details);
      expect(report.strideTimeAsymmetryPercent, closeTo(0, 0.001));
      expect(report.stanceTimeAsymmetryPercent, closeTo(0, 0.001));
    });

    test('reports nonzero stride-time asymmetry when feet differ', () {
      final asymLeft = _footLine([100, 0, 100, 0, 100, 0]);
      final asymRight = _footLine([100, 0, 0, 100, 0, 0]);
      final times = [0, 100, 200, 300, 400, 500];
      final asymDetails = [for (final t in times) PressureFrame(time: t, item: emptyGrid())];

      final report =
          ClinicalGaitAnalysis.analyze(line: asymLeft, rightLine: asymRight, details: asymDetails);
      // Left steps at samples 0,2,4 (t=0,200,400) -> stride time 200ms each.
      // Right steps at samples 0,3 (t=0,300) -> a single stride of 300ms.
      expect(report.left.strideTimeMeanMs, 200);
      expect(report.right.strideTimeMeanMs, 300);
      // symmetry index = |200-300| / 250 * 100 = 40%
      expect(report.strideTimeAsymmetryPercent, closeTo(40, 0.001));
    });

    test('handles no frame data without throwing', () {
      final report = ClinicalGaitAnalysis.analyze(
        line: FootLineData(),
        rightLine: FootLineData(),
        details: const [],
      );
      expect(report.left.stepCount, 0);
      expect(report.right.stepCount, 0);
      expect(report.cadenceStepsPerMin, isNull);
      expect(report.doubleSupportPercent, isNull);
    });
  });
}
