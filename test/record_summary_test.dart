import 'package:flutter_test/flutter_test.dart';
import 'package:solesync/models/foot_line_data.dart';
import 'package:solesync/models/foot_point_layout.dart';
import 'package:solesync/models/insole_record.dart';
import 'package:solesync/models/pressure_frame.dart';
import 'package:solesync/models/record_summary.dart';

void main() {
  group('FootLineData.fromFrames', () {
    test('reconstructs a foot\'s 16-point series from grid frames', () {
      final grid = emptyGrid();
      // FootPointLayout.left[0] == [0, 5].
      grid[0][5] = 77;

      final frames = [PressureFrame(time: 0, item: grid)];
      final line = FootLineData.fromFrames(frames, FootPointLayout.left);

      expect(line.series[0], [77]);
      expect(line.series[1], [0]);
    });
  });

  group('RecordSummary + InsoleRecord', () {
    test('round-trips through JSON without losing the clinical report', () {
      final details = [
        PressureFrame(time: 0, item: emptyGrid()),
        PressureFrame(time: 100, item: emptyGrid()),
      ];
      final summary = RecordSummary.compute(
        details: details,
        line: FootLineData(),
        rightLine: FootLineData(),
        elapsedSeconds: 1,
      );

      final record = InsoleRecord(
        id: 1,
        name: 'test',
        date: '2026-01-01 00:00',
        time: 1,
        summary: summary,
        framesFilePath: '/tmp/session_1.jsonl',
        distanceKm: 0,
        pace: 0,
        totalTime: 0,
        path: const [],
      );

      final restored = InsoleRecord.fromJson(record.toJson());
      expect(restored.framesFilePath, '/tmp/session_1.jsonl');
      expect(restored.summary.stepCount, summary.stepCount);
      expect(restored.summary.clinical.left.stepCount, summary.clinical.left.stepCount);
    });

    test('toJson never embeds raw frame data, however many frames were captured', () {
      // A record's JSON payload must stay small regardless of session
      // length -- this is what keeps it under Firestore's 1MB/doc limit
      // and out of the local storage blob.
      final manyFrames = List.generate(5000, (i) => PressureFrame(time: i * 20, item: emptyGrid()));
      final summary = RecordSummary.compute(
        details: manyFrames,
        line: FootLineData(),
        rightLine: FootLineData(),
        elapsedSeconds: 100,
      );
      final record = InsoleRecord(
        id: 1,
        name: 'long session',
        date: '2026-01-01 00:00',
        time: 100,
        summary: summary,
        framesFilePath: '/tmp/session_1.jsonl',
        distanceKm: 0,
        pace: 0,
        totalTime: 0,
        path: const [],
      );

      final json = record.toJson().toString();
      expect(json.length, lessThan(5000));
    });
  });
}
