import 'package:cloud_functions/cloud_functions.dart';

import '../models/record_summary.dart';
import 'gait_screening_model.dart';

/// Turns one session's already-computed metrics into a short plain-language
/// narrative, via the `generateSessionNarrative` Cloud Function (see
/// `functions/index.js`), which calls the Claude API server-side.
///
/// Deliberately sends only the small set of numbers this app has already
/// computed (cadence, asymmetry%, CV%, recovery/baseline/screening
/// findings) -- never raw sensor frames, and never the Anthropic API key,
/// which stays server-side in Secret Manager. This is a narration layer on
/// top of the app's own analysis, not a replacement for it: the model is
/// never asked to make a clinical judgment of its own, only to describe in
/// plain language the judgments `GaitScreeningModel`/`PersonalBaselineModel`/
/// `RecoveryAnalysis` already made.
class AiNarrativeService {
  AiNarrativeService._();

  /// Throws [AiNarrativeException] with a message safe to show directly in
  /// the UI (e.g. "Sign in required.", "Could not reach the narrative
  /// service.") -- never the raw Firebase/HTTP exception.
  static Future<String> generateSessionNarrative({
    required RecordSummary summary,
    String? recoverySummary,
    String? personalBaselineSummary,
    GaitScreeningResult? screening,
  }) async {
    final gait = summary.clinical;

    final metrics = {
      'stepCount': summary.stepCount,
      'cadenceSpm': summary.cadenceSpm,
      'groundContactMs': summary.groundContactMs,
      'flightMs': summary.flightMs,
      'rightLoadPercent': double.parse(summary.rightLoadPercent.toStringAsFixed(1)),
      'forefootPct': summary.forefootPct,
      'hindfootPct': summary.hindfootPct,
      'fogEventCount': summary.fogEventCount,
      'totalFreezeMs': summary.totalFreezeMs,
      'cadenceStepsPerMinClinical': gait.cadenceStepsPerMin,
      'doubleSupportPercent': gait.doubleSupportPercent,
      'singleSupportPercent': gait.singleSupportPercent,
      'strideTimeAsymmetryPercent': gait.strideTimeAsymmetryPercent,
      'stanceTimeAsymmetryPercent': gait.stanceTimeAsymmetryPercent,
      'leftStrideTimeCvPercent': gait.left.strideTimeCvPercent,
      'rightStrideTimeCvPercent': gait.right.strideTimeCvPercent,
    }..removeWhere((_, v) => v == null);

    final screeningBand = switch (screening?.band) {
      GaitScreeningBand.low => 'low signal',
      GaitScreeningBand.inconclusive => 'inconclusive',
      GaitScreeningBand.elevated => 'elevated signal',
      null => null,
    };

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('generateSessionNarrative');
      final result = await callable.call<Map<String, dynamic>>({
        'metrics': metrics,
        if (recoverySummary != null) 'recoverySummary': recoverySummary,
        if (personalBaselineSummary != null) 'personalBaselineSummary': personalBaselineSummary,
        if (screeningBand != null) 'screeningBand': screeningBand,
      });
      final narrative = result.data['narrative'] as String?;
      if (narrative == null || narrative.isEmpty) {
        throw const AiNarrativeException('The narrative service returned no text.');
      }
      return narrative;
    } on FirebaseFunctionsException catch (e) {
      throw AiNarrativeException(e.message ?? 'The narrative service returned an error.');
    } catch (e) {
      throw const AiNarrativeException('Could not reach the narrative service.');
    }
  }
}

class AiNarrativeException implements Exception {
  final String message;
  const AiNarrativeException(this.message);

  @override
  String toString() => message;
}
