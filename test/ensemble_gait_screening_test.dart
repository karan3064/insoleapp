import 'package:flutter_test/flutter_test.dart';
import 'package:solesync/services/clinical_gait_analysis.dart';
import 'package:solesync/services/ensemble_gait_screening.dart';
import 'package:solesync/services/gait_screening_model.dart';

/// Same fixture-building approach as test/gait_screening_model_test.dart --
/// reverse-engineers a minimal stride/swing/stance series whose mean/CV%
/// match the target values exactly, since `EnsembleGaitScreening` scores
/// through `ClinicalGaitReport`, not raw feature vectors directly.
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
  List<double> seriesForCv(double meanVal, double cvPercent) {
    final sd = cvPercent / 100 * meanVal;
    final d = sd / 1.4142135623730951;
    return [meanVal - d, meanVal + d];
  }

  FootGaitMetrics footFor(double strideCv, double swingCv, double stanceCv) {
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
  group('EnsembleGaitScreening', () {
    test('insufficientData when either model can\'t score the session', () {
      final result = EnsembleGaitScreening.evaluate(gait: ClinicalGaitReport.empty, speedMps: 1.1);
      expect(result.agreement, EnsembleAgreement.insufficientData);
      expect(result.logisticRegression, isNull);
      expect(result.randomForest, isNull);
    });

    test('agree when both models land on the same band -- extreme healthy-like input', () {
      // Verified against both the Python-trained logistic regression
      // (LR≈0.112 -> low) and the Python RandomForest (RF≈0.339 -> low)
      // for this exact feature vector before writing this assertion.
      final report = _reportFor(
        lStrideCv: 2.0, rStrideCv: 2.0, lSwingCv: 2.0, rSwingCv: 2.0,
        lStanceCv: 2.0, rStanceCv: 2.0, asym: 0.5, cadence: 120.0, dsupPct: 20.0,
      );
      final result = EnsembleGaitScreening.evaluate(gait: report, speedMps: 1.4);
      expect(result.logisticRegression!.band, GaitScreeningBand.low);
      expect(result.randomForest!.band, GaitScreeningBand.low);
      expect(result.agreement, EnsembleAgreement.agree);
    });

    test('agree when both models land on the same band -- extreme PD-like input', () {
      // LR≈0.997 -> elevated, RF≈0.970 -> elevated for this exact vector.
      final report = _reportFor(
        lStrideCv: 45.0, rStrideCv: 45.0, lSwingCv: 35.0, rSwingCv: 35.0,
        lStanceCv: 70.0, rStanceCv: 70.0, asym: 15.0, cadence: 70.0, dsupPct: 45.0,
      );
      final result = EnsembleGaitScreening.evaluate(gait: report, speedMps: 0.5);
      expect(result.logisticRegression!.band, GaitScreeningBand.elevated);
      expect(result.randomForest!.band, GaitScreeningBand.elevated);
      expect(result.agreement, EnsembleAgreement.agree);
    });

    test('disagree when the two models land on different bands', () {
      // Real PhysioNet trial feature vector: LR≈0.699 -> elevated,
      // RF≈0.476 -> inconclusive for this exact vector (both cross-checked
      // against the Python reference models before writing this test).
      final report = _reportFor(
        lStrideCv: 19.045196143553806, rStrideCv: 25.65452083080089,
        lSwingCv: 9.840541156902557, rSwingCv: 16.061349674676546,
        lStanceCv: 31.98147205750158, rStanceCv: 39.784206869786296,
        asym: 3.5970944690445568, cadence: 96.55696035387713, dsupPct: 29.24685570923976,
      );
      final result = EnsembleGaitScreening.evaluate(gait: report, speedMps: 1.075);
      expect(result.logisticRegression!.band, GaitScreeningBand.elevated);
      expect(result.randomForest!.band, GaitScreeningBand.inconclusive);
      expect(result.agreement, EnsembleAgreement.disagree);
    });
  });
}
