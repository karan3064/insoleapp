import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:solesync/models/fog_event.dart';
import 'package:solesync/services/freeze_index_detector.dart';

/// Feeds a synthetic sine wave of [hz] on top of [bias] (so the signal
/// never goes negative, like a real pressure sum) for [seconds], at a
/// native sample rate of [sampleHz], into a fresh detector.
FreezeIndexDetector _runSine({
  required double hz,
  required double amplitude,
  required double bias,
  double noiseFloor = 100,
  int sampleHz = 50,
  double seconds = 8,
}) {
  final detector = FreezeIndexDetector(noiseFloor: noiseFloor);
  final totalSamples = (sampleHz * seconds).round();
  for (var i = 0; i < totalSamples; i++) {
    final tMs = (i * 1000 / sampleHz).round();
    final value = bias + amplitude * math.sin(2 * math.pi * hz * tMs / 1000);
    detector.push(tMs, value);
  }
  return detector;
}

void main() {
  group('FreezeIndexDetector', () {
    test('a 1.5 Hz signal (normal cadence) never flags as freezing', () {
      final detector = _runSine(hz: 1.5, amplitude: 400, bias: 500);
      expect(detector.isFreezing, isFalse);
      expect(detector.events, isEmpty);
    });

    test('a 5 Hz signal (shuffling/freeze frequency) is flagged as freezing', () {
      final detector = _runSine(hz: 5, amplitude: 400, bias: 500);
      expect(detector.isFreezing, isTrue);
    });

    test('a flat near-zero signal (standing still) is never flagged', () {
      final detector = _runSine(hz: 5, amplitude: 2, bias: 5);
      expect(detector.isFreezing, isFalse);
    });

    test('a freeze episode that resolves back to normal cadence closes and fires onEvent', () {
      final detector = FreezeIndexDetector(noiseFloor: 100);
      FogEvent? fired;
      detector.onEvent = (e) => fired = e;

      const sampleHz = 50;
      void feedSeconds(double hz, double seconds, int startMs) {
        final totalSamples = (sampleHz * seconds).round();
        for (var i = 0; i < totalSamples; i++) {
          final tMs = startMs + (i * 1000 / sampleHz).round();
          final value = 500 + 400 * math.sin(2 * math.pi * hz * tMs / 1000);
          detector.push(tMs, value);
        }
      }

      feedSeconds(1.5, 8, 0); // normal walking
      expect(detector.isFreezing, isFalse);

      feedSeconds(5, 8, 8000); // freeze episode
      expect(detector.isFreezing, isTrue);

      feedSeconds(1.5, 8, 16000); // walking resumes
      expect(detector.isFreezing, isFalse);
      expect(detector.events, hasLength(1));
      expect(fired, isNotNull);
      expect(fired!.durationMs, greaterThan(0));
      expect(fired!.peakFreezeIndex, greaterThan(FreezeIndexDetector.freezeIndexThresholdOn));
    });
  });
}
