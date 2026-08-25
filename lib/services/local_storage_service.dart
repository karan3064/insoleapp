import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/insole_record.dart';
import '../models/user_profile.dart';

/// On-device persistence for saved test records + profile, mirroring the
/// Vue app's `vuex-persistedstate` setup (`store/index.js`).
class LocalStorageService {
  static const _recordsKey = 'insole_records';
  static const _profileKey = 'user_profile';
  static const maxRecords = 100;

  Future<List<InsoleRecord>> loadRecords() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_recordsKey);
    if (raw == null || raw.isEmpty) return [];

    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => InsoleRecord.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> saveRecords(List<InsoleRecord> records) async {
    final prefs = await SharedPreferences.getInstance();
    final capped = records.length > maxRecords ? records.sublist(0, maxRecords) : records;
    await prefs.setString(_recordsKey, jsonEncode(capped.map((r) => r.toJson()).toList()));
  }

  Future<UserProfile> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_profileKey);
    if (raw == null || raw.isEmpty) return UserProfile.empty;

    try {
      return UserProfile.fromJson(Map<String, dynamic>.from(jsonDecode(raw) as Map));
    } catch (_) {
      return UserProfile.empty;
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_profileKey, jsonEncode(profile.toJson()));
  }
}
