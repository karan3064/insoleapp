import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/user_profile.dart';
import '../services/firestore_sync_service.dart';
import '../services/local_storage_service.dart';

/// Email/password auth + profile, mirroring `store/modules/auth.js`.
class AuthProvider extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirestoreSyncService();
  final _localStorage = LocalStorageService();

  User? _user;
  UserProfile profile = UserProfile.empty;
  bool loading = false;

  /// Fires once with the newly-logged-in uid whenever sign in/up succeeds,
  /// so other providers (records) can hydrate from the cloud.
  void Function(String uid)? onLoggedIn;

  AuthProvider() {
    _auth.authStateChanges().listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  bool get isLoggedIn => _user != null;
  String? get uid => _user?.uid;
  String? get email => _user?.email;

  Future<void> loadLocalProfile() async {
    profile = await _localStorage.loadProfile();
    notifyListeners();
  }

  Future<String?> login(String email, String password) async {
    loading = true;
    notifyListeners();
    try {
      final cred = await _auth.signInWithEmailAndPassword(email: email, password: password);
      _user = cred.user;
      await hydrateProfile();
      if (_user != null) onLoggedIn?.call(_user!.uid);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Login failed';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<String?> signup(String email, String password) async {
    loading = true;
    notifyListeners();
    try {
      final cred = await _auth.createUserWithEmailAndPassword(email: email, password: password);
      _user = cred.user;
      await hydrateProfile();
      if (_user != null) onLoggedIn?.call(_user!.uid);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Signup failed';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _auth.signOut();
    profile = UserProfile.empty;
    notifyListeners();
  }

  Future<void> hydrateProfile() async {
    if (uid == null) return;
    try {
      final cloud = await _firestore.getProfile(uid!);
      if (cloud != null) {
        profile = cloud;
        await _localStorage.saveProfile(profile);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('hydrateProfile failed: $e');
    }
  }

  Future<void> updateProfile(UserProfile partial) async {
    profile = partial;
    await _localStorage.saveProfile(profile);
    notifyListeners();

    if (uid == null) return;
    try {
      await _firestore.setProfile(uid!, profile);
    } catch (e) {
      debugPrint('updateProfile sync failed: $e');
    }
  }
}
