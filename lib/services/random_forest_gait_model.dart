import 'clinical_gait_analysis.dart';
import 'gait_screening_model.dart';
import 'random_forest_trees.dart';

/// A second gait-pattern screening model -- same PhysioNet training data,
/// same 10 features, same honest subject-level cross-validation as
/// [GaitScreeningModel], but a Random Forest (25 decision trees, bootstrap-
/// aggregated) instead of a logistic regression. See
/// `tool/train_random_forest.py` for how it was trained and validated.
///
/// Honest result: ~70% accuracy, ~0.77 AUC across 30 subject-level splits
/// -- essentially TIED with [GaitScreeningModel]'s ~68%/0.78, not better.
/// With ~100 subjects, a different model architecture doesn't generalize
/// better, it just overfits differently -- this is not shipped as an
/// upgrade. It exists so [EnsembleGaitScreening] can check whether two
/// structurally-different models (linear vs. non-linear decision trees)
/// agree, which is a real uncertainty signal a single model can't give you.
class RandomForestGaitModel {
  RandomForestGaitModel._();

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
    final x = raw.map((v) => v!).toList(growable: false);
    return predictFromFeatures(x);
  }

  /// The feature vector must be, in order: left/right stride-time CV%,
  /// left/right swing-time CV%, left/right stance-time CV%, stride-time
  /// asymmetry%, cadence, double-support%, gait speed (m/s) -- exactly
  /// [GaitScreeningModel.predict]'s feature order. Exposed separately from
  /// [predict] so the ported tree-traversal logic can be tested against
  /// the Python-trained reference model's own predictions directly,
  /// without having to reverse-engineer synthetic stride/stance/swing
  /// time series that happen to produce exact target CV% values.
  static GaitScreeningResult predictFromFeatures(List<double> x) {
    final probability = _forestPredict(x);

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

  static double _forestPredict(List<double> x) {
    final sum = randomForestTrees.fold<double>(0, (acc, tree) => acc + _treePredict(tree, x));
    return sum / randomForestTrees.length;
  }

  static double _treePredict(List<Map<String, Object>> tree, List<double> x) {
    var node = tree[0];
    while (node['leaf'] != true) {
      final feature = node['feature'] as int;
      final threshold = node['threshold'] as double;
      final nextIndex = x[feature] <= threshold ? node['left'] as int : node['right'] as int;
      node = tree[nextIndex];
    }
    return node['value'] as double;
  }
}
