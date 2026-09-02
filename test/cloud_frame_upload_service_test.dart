import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('gzip compression used by CloudFrameUploadService', () {
    test('round-trips a JSONL frame file losslessly', () {
      // Mirrors the exact encode step `uploadFrames` runs on a session's
      // frame file before uploading -- if this doesn't round-trip, the
      // pipeline would receive corrupted data with no local symptom.
      const jsonl = '{"time":0,"item":[[0,0]]}\n{"time":50,"item":[[1,2]]}\n';
      final original = utf8.encode(jsonl);

      final compressed = GZipEncoder().encodeBytes(original);
      expect(compressed.length, greaterThan(0));

      final decompressed = GZipDecoder().decodeBytes(compressed);
      expect(utf8.decode(decompressed), jsonl);
    });
  });
}
