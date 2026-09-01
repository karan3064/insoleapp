import 'package:flutter/foundation.dart';

import '../models/insole_record.dart';
import '../services/firestore_sync_service.dart';
import '../services/local_storage_service.dart';
import '../services/session_file_store.dart';

/// Saved test records, mirroring `store/modules/insole.js`.
class InsoleProvider extends ChangeNotifier {
  final _localStorage = LocalStorageService();
  final _firestore = FirestoreSyncService();
  final _fileStore = SessionFileStore();

  List<InsoleRecord> list = [];
  bool loaded = false;

  Future<void> init() async {
    list = await _localStorage.loadRecords();
    loaded = true;
    notifyListeners();
  }

  int get nextId => list.isEmpty ? 1 : (list.map((r) => r.id).reduce((a, b) => a > b ? a : b) + 1);

  Future<void> saveRecord(InsoleRecord record) async {
    list = [record, ...list];
    if (list.length > LocalStorageService.maxRecords) {
      final evicted = list.sublist(LocalStorageService.maxRecords);
      list = list.sublist(0, LocalStorageService.maxRecords);
      await _deleteFrameFiles(evicted);
    }
    await _localStorage.saveRecords(list);
    notifyListeners();
  }

  /// Removes the local frame file for each evicted record so a session's
  /// raw data doesn't outlive the summary that references it -- otherwise
  /// these would accumulate on disk indefinitely as older sessions age out
  /// of the [LocalStorageService.maxRecords] cap.
  Future<void> _deleteFrameFiles(List<InsoleRecord> records) async {
    for (final r in records) {
      final path = r.framesFilePath;
      if (path != null) await _fileStore.deleteAtPath(path);
    }
  }

  Future<void> syncRecord(String? uid, InsoleRecord record) async {
    if (uid == null) return;
    try {
      await _firestore.setRecord(uid, record);
    } catch (e) {
      debugPrint('insole syncRecord failed: $e');
    }
  }

  Future<void> hydrateFromCloud(String? uid) async {
    if (uid == null) return;
    try {
      final cloud = await _firestore.listRecords(uid);
      final existingIds = list.map((r) => r.id).toSet();
      final merged = [...list, ...cloud.where((r) => !existingIds.contains(r.id))];
      merged.sort((a, b) => b.id.compareTo(a.id));
      if (merged.length > LocalStorageService.maxRecords) {
        await _deleteFrameFiles(merged.sublist(LocalStorageService.maxRecords));
        list = merged.sublist(0, LocalStorageService.maxRecords);
      } else {
        list = merged;
      }
      await _localStorage.saveRecords(list);
      notifyListeners();
    } catch (e) {
      debugPrint('insole hydrateFromCloud failed: $e');
    }
  }

  InsoleRecord? byId(int id) {
    for (final r in list) {
      if (r.id == id) return r;
    }
    return null;
  }
}
