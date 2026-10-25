// A standalone (non-Flutter) replay tool for bench-validating
// FreezeIndexDetector against a real recorded session, instead of only
// synthetic sine waves.
//
// Usage:
//   dart run tool/replay_fog_detector.dart <path/to/session_N.jsonl>
//
// Feeds every frame from a saved session's raw frame file (see
// `SessionFileStore` -- newline-delimited JSON, one PressureFrame per line)
// through the detector exactly the way `BleProvider._onData` does live, and
// prints every episode it flags with its start/end/peak-freeze-index. Run
// this against a session you recorded while also filming yourself (phone on
// a tripod, timestamp visible or a loud clap at t=0 to sync), then compare
// the printed timestamps against what you actually did in the video:
//
//   - A real freeze/shuffle in the video with no printed episode overlapping
//     it -> false negative (missed detection).
//   - A printed episode with no freeze/shuffle in the video at that time
//     -> false positive.
//   - A printed episode overlapping a real freeze in the video
//     -> true positive.
//
// That gives you an honest sensitivity/false-positive-rate estimate without
// needing a clinical setting -- just you, your insoles, and a phone camera.
// Re-run this after editing the thresholds in `freeze_index_detector.dart`
// to tune them against the same recording before re-testing live.

import 'dart:convert';
import 'dart:io';

import 'package:solesync/models/pressure_frame.dart';
import 'package:solesync/services/freeze_index_detector.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/replay_fog_detector.dart <path/to/session.jsonl>');
    exit(1);
  }

  final file = File(args[0]);
  if (!await file.exists()) {
    stderr.writeln('No such file: ${args[0]}');
    exit(1);
  }

  final frames = <PressureFrame>[];
  await for (final line in file.openRead().transform(utf8.decoder).transform(const LineSplitter())) {
    if (line.isEmpty) continue;
    try {
      frames.add(PressureFrame.fromJson(jsonDecode(line) as Map<String, dynamic>));
    } catch (e) {
      stderr.writeln('Skipping corrupt line: $e');
    }
  }

  if (frames.isEmpty) {
    stderr.writeln('No frames found in ${args[0]}');
    exit(1);
  }

  print('Loaded ${frames.length} frames spanning '
      '${((frames.last.time - frames.first.time) / 1000).toStringAsFixed(1)}s');

  final detector = FreezeIndexDetector();
  var episodeIndex = 0;
  detector.onEvent = (event) {
    episodeIndex++;
    print('Episode #$episodeIndex: ${_fmt(event.startMs)} -> ${_fmt(event.endMs)} '
        '(${(event.durationMs / 1000).toStringAsFixed(1)}s, '
        'peak freeze index ${event.peakFreezeIndex.toStringAsFixed(2)})');
  };

  for (final frame in frames) {
    final total = frame.item.fold<int>(0, (sum, row) => sum + row.fold<int>(0, (s, v) => s + v));
    detector.push(frame.time, total);
  }

  if (detector.isFreezing) {
    print('(signal was still in a freeze state when the recording ended)');
  }
  if (episodeIndex == 0) {
    print('No episodes detected in this session.');
  }
}

String _fmt(int ms) {
  final totalSeconds = ms / 1000;
  final mins = (totalSeconds / 60).floor();
  final secs = totalSeconds - mins * 60;
  return '${mins}m${secs.toStringAsFixed(1)}s';
}
