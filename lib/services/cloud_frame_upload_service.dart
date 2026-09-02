import 'dart:io';

import 'package:archive/archive.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// Uploads a session's raw local frame file (see `SessionFileStore`) to
/// Firebase Cloud Storage, gzip-compressed. This is the raw signal a
/// future server-side ML pipeline (e.g. freezing-of-gait detection) would
/// need -- Firestore's 1MB/doc limit rules out storing it there, and
/// `RecordSummary` only ever carries the small, already-computed numbers.
///
/// The local copy is never deleted after upload -- it stays the source of
/// truth for on-device playback/export. This is purely an additional,
/// best-effort copy for future cloud-side processing.
class CloudFrameUploadService {
  final _storage = FirebaseStorage.instance;

  /// Uploads [localPath]'s contents to
  /// `users/{uid}/sessions/{sessionRecordId}.jsonl.gz`. Returns the
  /// storage path on success, or null if there was nothing to upload or
  /// the upload failed -- callers should treat this the same as Firestore
  /// sync: best-effort, never blocking session saving on it.
  Future<String?> uploadFrames({
    required String uid,
    required int sessionRecordId,
    required String localPath,
  }) async {
    final file = File(localPath);
    if (!await file.exists()) return null;

    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) return null;

    final compressed = GZipEncoder().encodeBytes(bytes);
    final storagePath = 'users/$uid/sessions/$sessionRecordId.jsonl.gz';

    await _storage.ref(storagePath).putData(
          compressed,
          SettableMetadata(contentType: 'application/gzip', contentEncoding: 'gzip'),
        );

    return storagePath;
  }
}
