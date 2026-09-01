import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/pressure_frame.dart';

/// Persists one session's raw per-frame pressure data to a local file
/// instead of an in-memory list, so a long (e.g. multi-hour) capture
/// doesn't have to hold every frame resident in RAM for its whole
/// duration -- only this session's file grows, not the app's heap.
///
/// Format is newline-delimited JSON (one [PressureFrame] per line) so
/// frames can be appended one at a time during capture without rewriting
/// the whole file.
class SessionFileStore {
  Future<Directory> _sessionsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/sessions');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> fileFor(int sessionId) async {
    final dir = await _sessionsDir();
    return File('${dir.path}/session_$sessionId.jsonl');
  }

  /// Opens (creating/truncating) the file for [sessionId] for appending
  /// frames as they're captured.
  Future<IOSink> openWriter(int sessionId) async {
    final file = await fileFor(sessionId);
    return file.openWrite(mode: FileMode.writeOnly);
  }

  void writeFrame(IOSink sink, PressureFrame frame) {
    sink.writeln(jsonEncode(frame.toJson()));
  }

  /// Reads back every frame written for [sessionId], in the order they
  /// were captured. Returns an empty list if the session has no local
  /// file (e.g. it was synced from another device rather than recorded
  /// on this one).
  Future<List<PressureFrame>> readFrames(int sessionId) async {
    return readFramesAtPath((await fileFor(sessionId)).path);
  }

  /// Same as [readFrames], but reads directly from a known file path
  /// (e.g. `InsoleRecord.framesFilePath`) instead of re-deriving it from
  /// a session id.
  Future<List<PressureFrame>> readFramesAtPath(String path) async {
    final file = File(path);
    if (!await file.exists()) return [];

    final frames = <PressureFrame>[];
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      if (line.isEmpty) continue;
      try {
        frames.add(PressureFrame.fromJson(jsonDecode(line) as Map<String, dynamic>));
      } catch (_) {
        // Skip a corrupt line (e.g. a partially-flushed write after a
        // crash) rather than losing the rest of the session.
      }
    }
    return frames;
  }

  Future<void> deleteSession(int sessionId) async {
    await deleteAtPath((await fileFor(sessionId)).path);
  }

  /// Same as [deleteSession], but by a known file path (e.g. an evicted
  /// `InsoleRecord.framesFilePath`) instead of a session id.
  Future<void> deleteAtPath(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
