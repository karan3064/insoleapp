import 'clinical_gait_analysis.dart';
import 'gait_screening_model.dart';
import 'random_forest_gait_model.dart';

/// How two structurally-different gait-screening models (a linear model
/// and a non-linear decision-tree ensemble) relate to each other on the
/// same session -- a real uncertainty signal neither model can give alone.
enum EnsembleAgreement {
  /// Both models landed on the same band -- the closest this app gets to
  /// "more confident," still never a diagnosis.
  agree,

  /// The two models landed on different bands -- a genuine reason to call
  /// the result inconclusive, not noise to average away.
  disagree,

  /// Either model couldn't score this session (missing gait-cycle data).
  insufficientData,
}

class EnsembleGaitScreeningResult {
  final GaitScreeningResult? logisticRegression;
  final GaitScreeningResult? randomForest;
  final EnsembleAgreement agreement;

  const EnsembleGaitScreeningResult({
    required this.logisticRegression,
    required this.randomForest,
    required this.agreement,
  });
}

/// Runs both of this app's independently-trained gait-screening models
/// (see `GaitScreeningModel` and `RandomForestGaitModel` for how each was
/// trained and honestly validated) on the same session, and reports
/// whether they agree.
///
/// This is NOT presented as "two models voting make the result more
/// accurate" -- cross-validated, the two score almost identically on the
/// same data (see both models' doc comments), so neither outvotes the
/// other. What agreement between two differently-structured models
/// legitimately buys you: when they land on the same band, that band
/// wasn't an artifact of one model's particular assumptions; when they
/// disagree, that's a real, honest reason to treat the session as
/// inconclusive rather than quietly picking one model's answer.
class EnsembleGaitScreening {
  EnsembleGaitScreening._();

  static EnsembleGaitScreeningResult evaluate({
    required ClinicalGaitReport gait,
    required double? speedMps,
  }) {
    final lr = GaitScreeningModel.predict(gait: gait, speedMps: speedMps);
    final rf = RandomForestGaitModel.predict(gait: gait, speedMps: speedMps);

    final EnsembleAgreement agreement;
    if (lr == null || rf == null) {
      agreement = EnsembleAgreement.insufficientData;
    } else if (lr.band == rf.band) {
      agreement = EnsembleAgreement.agree;
    } else {
      agreement = EnsembleAgreement.disagree;
    }

    return EnsembleGaitScreeningResult(
      logisticRegression: lr,
      randomForest: rf,
      agreement: agreement,
    );
  }
}
