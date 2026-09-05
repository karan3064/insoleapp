import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/family_contact.dart';
import '../models/safe_zone.dart';

/// Cloud storage for the geofencing/safety feature: the patient's safe
/// zone, their family contacts list, and breach events.
///
/// IMPORTANT -- this needs a Firestore security rule this repo can't set
/// for you (there's no `firestore.rules` file here; whatever's deployed
/// on the `solesync-f7740` console today almost certainly does NOT allow
/// this). [registerContactToken] is called from a family member's own
/// device, writing into the *patient's* document tree -- a per-user rule
/// like `request.auth.uid == uid` would reject it. You need a rule along
/// these lines for `users/{uid}/familyContacts/{contactId}`:
///
///   allow update: if request.auth != null
///     && request.resource.data.diff(resource.data).affectedKeys()
///          .hasOnly(['fcmToken']);
///
/// (i.e. any signed-in user may update only the `fcmToken` field of an
/// *existing* contact doc, never create/delete one or touch name/email --
/// the invite code is the shared secret that limits who can do this in
/// practice, since you need the contact's id to target it at all).
class GeofenceService {
  final _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _safety(String uid) =>
      _db.collection('users').doc(uid).collection('safety');

  CollectionReference<Map<String, dynamic>> _contacts(String uid) =>
      _db.collection('users').doc(uid).collection('familyContacts');

  Future<void> setSafeZone(String uid, SafeZone zone) async {
    await _safety(uid).doc('safeZone').set(zone.toJson());
  }

  Future<SafeZone?> getSafeZone(String uid) async {
    final doc = await _safety(uid).doc('safeZone').get();
    final data = doc.data();
    if (data == null) return null;
    return SafeZone.fromJson(data);
  }

  Future<void> deleteSafeZone(String uid) async {
    await _safety(uid).doc('safeZone').delete();
  }

  Future<String> addFamilyContact(String uid, {required String name, required String email}) async {
    final ref = await _contacts(uid).add({'name': name, 'email': email, 'fcmToken': null});
    return ref.id;
  }

  Future<List<FamilyContact>> listFamilyContacts(String uid) async {
    final snap = await _contacts(uid).get();
    return snap.docs.map((d) => FamilyContact.fromJson(d.id, d.data())).toList();
  }

  Future<void> removeFamilyContact(String uid, String contactId) async {
    await _contacts(uid).doc(contactId).delete();
  }

  /// Called from the family member's own device once they enter an invite
  /// code -- attaches their device's push token to the patient's contact
  /// doc so future breach alerts reach them too, not just by email.
  Future<void> registerContactToken({
    required String patientUid,
    required String contactId,
    required String fcmToken,
  }) async {
    await _contacts(patientUid).doc(contactId).set({'fcmToken': fcmToken}, SetOptions(merge: true));
  }

  /// Records a safe-zone breach detected on the patient's device. Actually
  /// notifying family contacts (push + email) is a Cloud Function's job
  /// (see `functions/`), triggered by this write -- kept server-side so
  /// delivery doesn't depend on the patient's device staying online after
  /// this call succeeds.
  Future<void> recordBreach(
    String uid, {
    required double latitude,
    required double longitude,
    required double distanceMeters,
  }) async {
    await _db.collection('users').doc(uid).collection('geofenceAlerts').add({
      'latitude': latitude,
      'longitude': longitude,
      'distanceMeters': distanceMeters,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }
}
