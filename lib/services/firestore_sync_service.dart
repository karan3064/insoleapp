import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/insole_record.dart';
import '../models/user_profile.dart';

/// Cloud sync for profile + insole test records, mirroring
/// `store/modules/auth.js` and `store/modules/insole.js` (`setDocument`,
/// `getDocument`, `listDocuments` calls against Firestore).
class FirestoreSyncService {
  final _db = FirebaseFirestore.instance;

  Future<void> setProfile(String uid, UserProfile profile) async {
    await _db.collection('users').doc(uid).set(profile.toJson());
  }

  Future<UserProfile?> getProfile(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    if (!doc.exists) return null;
    return UserProfile.fromJson(doc.data()!);
  }

  Future<void> setRecord(String uid, InsoleRecord record) async {
    await _db
        .collection('users')
        .doc(uid)
        .collection('insoleRecords')
        .doc(record.id.toString())
        .set(record.toJson());
  }

  Future<List<InsoleRecord>> listRecords(String uid) async {
    final snap = await _db.collection('users').doc(uid).collection('insoleRecords').get();
    return snap.docs.map((d) => InsoleRecord.fromJson(d.data())).toList();
  }
}
