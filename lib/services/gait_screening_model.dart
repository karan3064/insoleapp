import 'dart:math' as math;

import 'clinical_gait_analysis.dart';

/// Qualitative bucket for [GaitScreeningModel.predict]'s output -- a raw
/// percentage would read as more precise than this model actually is (see
/// the class doc), so the UI only ever shows one of these three bands.
enum GaitScreeningBand { low, inconclusive, elevated }

class GaitScreeningResult {
  final double probability;
  final GaitScreeningBand band;
  const GaitScreeningResult(this.probability, this.band);
}

/// A gait-pattern screening signal -- NOT a diagnosis -- trained offline on
/// the PhysioNet "Gait in Parkinson's Disease" database (Frenkel-Toledo,
/// Hausdorff, Yogev et al.; 143 real recorded trials, 99 subjects: PD
/// patients and age-matched healthy controls walking at their usual pace).
///
/// What this is: a small, interpretable logistic regression over 10
/// features this app already computes for every session (per-side stride/
/// swing/stance-time variability, L/R asymmetry, cadence, double-support%)
/// plus gait speed. Chosen deliberately over anything more complex --
/// with ~100 subjects' worth of training data, a bigger model would just
/// memorize noise and report false confidence.
///
/// Honest performance, from subject-level held-out cross-validation (30
/// random splits, no subject's trials ever split across train/test):
/// accuracy ~68%, AUC ~0.78. That is FAIR discrimination, not clinical-
/// grade. Context: a same-architecture model using only the 4 most
/// "obvious" features (stride-time CV, swing-time CV, asymmetry, cadence,
/// each averaged across feet) scored only ~62% accuracy / 0.67 AUC --
/// barely above the 63% you'd get by always guessing "PD" given this
/// dataset's class balance. The features added here (per-side rather than
/// averaged, stance-time variability, double-support%, and especially gait
/// speed, which alone reaches 0.73 AUC) are what moved it into the
/// "actually somewhat useful as a screening nudge" range.
///
/// Known limitations, not hidden:
///  - Trained on 8-sensor force-plate recordings from a research lab, not
///    this app's own 16-point insole hardware or real-world GPS-derived
///    speed -- applying it to this app's data is a real domain shift this
///    model has never been validated against.
///  - 99 subjects is a small training set for 10 features; the 30-split
///    cross-validation range was wide (~53%-83% accuracy depending on the
///    split), so treat the point estimates above as the honest middle of
///    real uncertainty, not a guarantee.
///  - PD-vs-control overlap in the predicted probability was substantial
///    (control subjects ranged up to 0.84, PD patients as low as 0.24) --
///    this is why the result is bucketed into three bands, not shown as a
///    precise percentage.
class GaitScreeningModel {
  GaitScreeningModel._();

  static const _featureMeans = [
    17.576997, 15.960473, 10.938149, 11.10496, 25.940264,
    28.237863, 2.522488, 107.160751, 34.175683, 1.091986,
  ];
  static const _featureSds = [
    18.752334, 16.614493, 6.398685, 6.305575, 24.460347,
    44.383284, 5.778057, 12.67436, 9.865663, 0.206729,
  ];
  static const _weights = [
    0.120584, 0.288249, 0.281635, 0.115545, 0.140107,
    0.185935, -0.070596, 0.113005, 0.665686, -0.688958,
  ];
  static const _bias = 0.921998;

  /// Returns null if any required input is unavailable (e.g. no steps
  /// detected on one side, or no usable gait-speed estimate), rather than
  /// guessing with a partial feature vector.
  static GaitScreeningResult? predict({
    required ClinicalGaitReport gait,
    required double? speedMps,
  }) {
    final raw = [
      gait.left.strideTimeCvPercent,
      gait.right.strideTimeCvPercent,
      gait.left.swingTimeCvPercent,
      gait.right.swingTimeCvPercent,
      gait.left.stanceTimeCvPercent,
      gait.right.stanceTimeCvPercent,
      gait.strideTimeAsymmetryPercent,
      gait.cadenceStepsPerMin,
      gait.doubleSupportPercent,
      speedMps,
    ];
    if (raw.any((v) => v == null)) return null;

    var z = _bias;
    for (var i = 0; i < raw.length; i++) {
      final standardized = (raw[i]! - _featureMeans[i]) / _featureSds[i];
      z += _weights[i] * standardized;
    }
    final probability = 1 / (1 + math.exp(-z));

    final GaitScreeningBand band;
    if (probability < 0.45) {
      band = GaitScreeningBand.low;
    } else if (probability > 0.65) {
      band = GaitScreeningBand.elevated;
    } else {
      band = GaitScreeningBand.inconclusive;
    }

    return GaitScreeningResult(probability, band);
  }
}
