import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/mood_entry.dart';

/// Cloud storage for daily mood check-ins. Unlike `GeofenceService`'s
/// family-contacts collection, this needs no special cross-user Firestore
/// rule -- every document here is written and read only by the signed-in
/// patient themselves (`users/{uid}/moodEntries/{dateKey}`), so the
/// standard "a user can only touch their own `users/{uid}` subtree" rule
/// that the rest of this app already needs covers it.
class MoodService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _entries(String uid) =>
      _db.collection('users').doc(uid).collection('moodEntries');

  /// One check-in per calendar day -- a second check-in the same day
  /// overwrites the first rather than creating a duplicate, since "how are
  /// you feeling today" only has one answer per day.
  Future<void> checkIn(String uid, {required int score, String? note}) async {
    final entry = MoodEntry(id: MoodEntry.dateKey(DateTime.now()), date: DateTime.now(), score: score, note: note);
    await _entries(uid).doc(entry.id).set(entry.toJson());
  }

  Future<MoodEntry?> todayEntry(String uid) async {
    final id = MoodEntry.dateKey(DateTime.now());
    final doc = await _entries(uid).doc(id).get();
    final data = doc.data();
    if (data == null) return null;
    return MoodEntry.fromJson(doc.id, data);
  }

  /// Most recent entries first. [limit] bounds the read -- the correlation
  /// engine and any trend UI only ever need a recent window, not the
  /// patient's entire history.
  Future<List<MoodEntry>> recentEntries(String uid, {int limit = 60}) async {
    final snap = await _entries(uid).orderBy('date', descending: true).limit(limit).get();
    return snap.docs.map((d) => MoodEntry.fromJson(d.id, d.data())).toList();
  }
}
