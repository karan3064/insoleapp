import 'package:cloud_functions/cloud_functions.dart';

/// The two AI touchpoints outside a single session's detail screen: the
/// home screen's personalized greeting, and a reply to a daily mood
/// check-in. Same Cloud Functions pattern as `AiNarrativeService`
/// (`generateHomeInsight`/`respondToMoodCheckIn`, see `functions/index.js`)
/// -- never the raw Anthropic/Gemini key on the client, never raw sensor
/// data sent, only small derived context.
class HomeAiService {
  HomeAiService._();

  /// [context] should be a small, already-derived JSON-safe map (session
  /// count, recovery/baseline summaries, time of day) -- never raw frames.
  /// Returns null on any failure rather than throwing, since a missing
  /// greeting should fall back to a generic one, not block the home screen.
  static Future<String?> generateHomeInsight(Map<String, dynamic> context) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('generateHomeInsight');
      final result = await callable.call<Map<String, dynamic>>({'context': context});
      final greeting = result.data['greeting'] as String?;
      return (greeting == null || greeting.isEmpty) ? null : greeting;
    } catch (_) {
      return null;
    }
  }

  /// Returns null on any failure -- a missing AI reply to a mood check-in
  /// should silently fall back to a static acknowledgment, not block the
  /// check-in from being saved.
  static Future<String?> respondToMoodCheckIn({required int score, String? note}) async {
    try {
      final callable = FirebaseFunctions.instance.httpsCallable('respondToMoodCheckIn');
      final result = await callable.call<Map<String, dynamic>>({
        'score': score,
        if (note != null && note.isNotEmpty) 'note': note,
      });
      final reply = result.data['reply'] as String?;
      return (reply == null || reply.isEmpty) ? null : reply;
    } on FirebaseFunctionsException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
