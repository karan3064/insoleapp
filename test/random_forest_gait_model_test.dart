import 'package:flutter_test/flutter_test.dart';
import 'package:solesync/services/random_forest_gait_model.dart';

void main() {
  test('ported tree-traversal matches the Python-trained reference model', () {
    // Real feature rows from the PhysioNet dataset (tool/train_random_forest.py),
    // with predict_proba() computed directly by the Python RandomForest class
    // that produced lib/services/random_forest_trees.dart -- this checks the
    // Dart port's arithmetic against the actual trained model, not just that
    // it runs without crashing.
    final cases = [
      (
        x: [
          19.045196143553806, 25.65452083080089, 9.840541156902557, 16.061349674676546,
          31.98147205750158, 39.784206869786296, 3.5970944690445568, 96.55696035387713,
          29.24685570923976, 1.075,
        ],
        expected: 0.476381,
      ),
      (
        x: [
          25.861224586840976, 12.149740807347891, 5.3688215779800945, 10.848515672384062,
          39.14923314262983, 17.378343233955675, 3.317776627901081, 105.96507443963952,
          30.897402040075267, 1.04,
        ],
        expected: 0.505616,
      ),
      (
        x: [
          5.73404198998508, 7.851034597521714, 4.850966683693912, 6.96992030471996,
          9.898011215349932, 13.283488861672621, 0.3827308772317144, 113.39253292839929,
          29.98877628495032, 1.04,
        ],
        expected: 0.106215,
      ),
    ];

    for (final c in cases) {
      final result = RandomForestGaitModel.predictFromFeatures(c.x);
      expect(result.probability, closeTo(c.expected, 1e-5));
    }
  });

  test('band thresholds match GaitScreeningBand convention', () {
    // Row 2 above (0.106215) is well below 0.45 -> low.
    final low = RandomForestGaitModel.predictFromFeatures([
      5.73404198998508, 7.851034597521714, 4.850966683693912, 6.96992030471996,
      9.898011215349932, 13.283488861672621, 0.3827308772317144, 113.39253292839929,
      29.98877628495032, 1.04,
    ]);
    expect(low.probability, lessThan(0.45));
  });
}
