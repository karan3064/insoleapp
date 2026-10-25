import 'package:cloud_functions/cloud_functions.dart';

import '../models/record_summary.dart';
import 'gait_screening_model.dart';

enum ChatRole { user, assistant }

class ChatMessage {
  final ChatRole role;
  final String content;
  const ChatMessage({required this.role, required this.content});
}

/// Turns one session's already-computed metrics into a short plain-language
/// narrative (`generateSessionNarrative`), and answers follow-up questions
/// about them (`chatAboutSession`) -- both via Cloud Functions (see
/// `functions/index.js`) that call the Claude API server-side.
///
/// Deliberately sends only the small set of numbers this app has already
/// computed (cadence, asymmetry%, CV%, recovery/baseline/screening
/// findings) -- never raw sensor frames, and never the Anthropic API key,
/// which stays server-side in Secret Manager. This is a narration/Q&A layer
/// on top of the app's own analysis, not a replacement for it: the model is
/// never asked to make a clinical judgment of its own, only to describe in
/// plain language the judgments `GaitScreeningModel`/`PersonalBaselineModel`/
/// `RecoveryAnalysis` already made (the chat's system prompt, server-side,
/// is additionally told never to diagnose or prescribe treatment, and to
/// redirect "what should I do" to the patient's own clinician).
class AiNarrativeService {
  AiNarrativeService._();

  /// Only the most recent messages in a chat are sent per call -- stateless
  /// server-side, so a long-running conversation shouldn't grow the request
  /// (and the token cost) without bound.
  static const maxChatMessagesSent = 20;

  /// Throws [AiNarrativeException] with a message safe to show directly in
  /// the UI (e.g. "Sign in required.", "Could not reach the narrative
  /// service.") -- never the raw Firebase/HTTP exception.
  static Future<String> generateSessionNarrative({
    required RecordSummary summary,
    String? recoverySummary,
    String? personalBaselineSummary,
    GaitScreeningResult? screening,
  }) async {
    final result = await _call('generateSessionNarrative', {
      'metrics': _buildMetrics(summary),
      if (recoverySummary != null) 'recoverySummary': recoverySummary,
      if (personalBaselineSummary != null) 'personalBaselineSummary': personalBaselineSummary,
      if (_screeningBandLabel(screening) != null) 'screeningBand': _screeningBandLabel(screening),
    });
    final narrative = result['narrative'] as String?;
    if (narrative == null || narrative.isEmpty) {
      throw const AiNarrativeException('The narrative service returned no text.');
    }
    return narrative;
  }

  /// [history] should include the new user message as its last entry.
  static Future<String> sendChatMessage({
    required RecordSummary summary,
    required List<ChatMessage> history,
    String? recoverySummary,
    String? personalBaselineSummary,
    GaitScreeningResult? screening,
  }) async {
    final trimmed = history.length > maxChatMessagesSent
        ? history.sublist(history.length - maxChatMessagesSent)
        : history;

    final result = await _call('chatAboutSession', {
      'metrics': _buildMetrics(summary),
      if (recoverySummary != null) 'recoverySummary': recoverySummary,
      if (personalBaselineSummary != null) 'personalBaselineSummary': personalBaselineSummary,
      if (_screeningBandLabel(screening) != null) 'screeningBand': _screeningBandLabel(screening),
      'messages': trimmed
          .map((m) => {'role': m.role == ChatRole.user ? 'user' : 'assistant', 'content': m.content})
          .toList(),
    });
    final reply = result['reply'] as String?;
    if (reply == null || reply.isEmpty) {
      throw const AiNarrativeException('The assistant returned no reply.');
    }
    return reply;
  }

  static Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(name);
      final result = await callable.call<Map<String, dynamic>>(data);
      return result.data;
    } on FirebaseFunctionsException catch (e) {
      throw AiNarrativeException(e.message ?? 'The assistant returned an error.');
    } on AiNarrativeException {
      rethrow;
    } catch (e) {
      throw const AiNarrativeException('Could not reach the assistant.');
    }
  }

  static Map<String, dynamic> _buildMetrics(RecordSummary summary) {
    final gait = summary.clinical;
    return {
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
  }

  static String? _screeningBandLabel(GaitScreeningResult? screening) => switch (screening?.band) {
        GaitScreeningBand.low => 'low signal',
        GaitScreeningBand.inconclusive => 'inconclusive',
        GaitScreeningBand.elevated => 'elevated signal',
        null => null,
      };
}

class AiNarrativeException implements Exception {
  final String message;
  const AiNarrativeException(this.message);

  @override
  String toString() => message;
}
