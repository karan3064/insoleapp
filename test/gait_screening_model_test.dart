import 'package:flutter_test/flutter_test.dart';
import 'package:solesync/services/clinical_gait_analysis.dart';
import 'package:solesync/services/gait_screening_model.dart';

/// Builds a [ClinicalGaitReport] directly from pre-computed per-foot
/// stride/swing/stance-time lists and an explicit double-support%, instead
/// of synthesizing raw pressure frames -- this test only cares about
/// whether [GaitScreeningModel] reproduces the exact probabilities the
/// Python training script produced for known feature vectors, not about
/// `ClinicalGaitAnalysis`'s own event-detection (covered by its own test).
ClinicalGaitReport _reportFor({
  required double lStrideCv,
  required double rStrideCv,
  required double lSwingCv,
  required double rSwingCv,
  required double lStanceCv,
  required double rStanceCv,
  required double asym,
  required double cadence,
  required double dsupPct,
}) {
  // Reverse-engineer a minimal stride/swing/stance list (2 cycles) whose
  // mean/CV% match the target values exactly, for each foot.
  List<double> seriesForCv(double meanVal, double cvPercent) {
    // Two points {m-d, m+d} have mean m and sample stdDev d*sqrt(2)
    // (ClinicalGaitAnalysis._stdDev's n-1 convention) -- solving for the
    // target sd = cvPercent/100*meanVal gives d = sd/sqrt(2).
    final sd = cvPercent / 100 * meanVal;
    final d = sd / 1.4142135623730951;
    return [meanVal - d, meanVal + d];
  }

  FootGaitMetrics footFor(double strideCv, double swingCv, double stanceCv) {
    // Pick arbitrary means (ms) consistent with typical gait, matching
    // what each CV% implies for the fixed means used below.
    const strideMean = 1100.0;
    const swingMean = 420.0;
    const stanceMean = 680.0;
    return FootGaitMetrics(
      stepCount: 3,
      strideTimesMs: seriesForCv(strideMean, strideCv),
      swingTimesMs: seriesForCv(swingMean, swingCv),
      stanceTimesMs: seriesForCv(stanceMean, stanceCv),
    );
  }

  return ClinicalGaitReport(
    left: footFor(lStrideCv, lSwingCv, lStanceCv),
    right: footFor(rStrideCv, rSwingCv, rStanceCv),
    cadenceStepsPerMin: cadence,
    doubleSupportPercent: dsupPct,
    singleSupportPercent: 100 - dsupPct,
    strideTimeAsymmetryPercent: asym,
    stanceTimeAsymmetryPercent: 0,
  );
}

void main() {
  group('GaitScreeningModel', () {
    test('returns null when a required input is missing', () {
      final report = ClinicalGaitReport.empty;
      final result = GaitScreeningModel.predict(gait: report, speedMps: 1.1);
      expect(result, isNull);
    });

    test('returns null when speed is unavailable', () {
      final report = _reportFor(
        lStrideCv: 19.05, rStrideCv: 25.65, lSwingCv: 9.84, rSwingCv: 16.06,
        lStanceCv: 31.98, rStanceCv: 39.78, asym: 3.60, cadence: 96.56, dsupPct: 29.25,
      );
      expect(GaitScreeningModel.predict(gait: report, speedMps: null), isNull);
    });

    // Fixtures below: exact feature vectors + expected probabilities from
    // the Python training script this model's weights were fit with
    // (see `GaitScreeningModel`'s doc comment for the full methodology).
    test('reproduces the trained model\'s output for known feature vectors', () {
      final r1 = _reportFor(
        lStrideCv: 19.045196143553806, rStrideCv: 25.65452083080089,
        lSwingCv: 9.840541156902557, rSwingCv: 16.061349674676546,
        lStanceCv: 31.98147205750158, rStanceCv: 39.784206869786296,
        asym: 3.5970944690445568, cadence: 96.55696035387713, dsupPct: 29.24685570923976,
      );
      final result1 = GaitScreeningModel.predict(gait: r1, speedMps: 1.075);
      expect(result1, isNotNull);
      expect(result1!.probability, closeTo(0.698775, 0.0005));
      expect(result1.band, GaitScreeningBand.elevated);

      final r2 = _reportFor(
        lStrideCv: 2.4786180828217583, rStrideCv: 1.7211697813221516,
        lSwingCv: 5.498102121206441, rSwingCv: 3.9146926970270615,
        lStanceCv: 3.6583671781571327, rStanceCv: 7.686483576956797,
        asym: 0.19911724687220295, cadence: 106.95540223814082, dsupPct: 29.38715214736078,
      );
      final result2 = GaitScreeningModel.predict(gait: r2, speedMps: 1.16);
      expect(result2, isNotNull);
      expect(result2!.probability, closeTo(0.370454, 0.0005));
      expect(result2.band, GaitScreeningBand.low);
    });
  });
}
