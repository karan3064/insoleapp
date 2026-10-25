import 'dart:math' as math;

import '../models/fog_event.dart';

/// Real-time Freezing-of-Gait (FOG) detector running on the insole's
/// combined pressure signal.
///
/// This implements the "freeze index" method from Bachlin et al., 2010
/// ("Wearable Assistant for Parkinson's Disease Patients With the Freezing
/// of Gait Symptom", IEEE Trans. Information Technology in Biomedicine) --
/// originally built around a shank-mounted accelerometer, adapted here to
/// the insole's total vertical loading signal (sum of all pressure cells),
/// which oscillates with each step the same way a shank accelerometer's
/// vertical axis does.
///
/// During normal walking, that signal's spectral power concentrates in the
/// "locomotor band" (~0.5-3 Hz, the stride frequency). During a freezing
/// episode, the leg trembles/shuffles at a higher frequency instead, so
/// power shifts into the "freeze band" (~3-8 Hz). The freeze index is
/// `freezeBandPower / locomotorBandPower`: it spikes during a freeze and
/// stays low during fluent walking.
///
/// This is a real signal-processing detector, not a trained model -- it
/// makes no diagnostic claim, and [freezeIndexThresholdOn]/[noiseFloor]
/// are starting points from the literature that should be tuned against
/// real recorded freezing episodes from this hardware before being relied
/// on clinically.
class FreezeIndexDetector {
  /// Uniform resample rate used for the FFT window. 20 Hz gives a Nyquist
  /// of 10 Hz, comfortably above the 8 Hz freeze-band edge.
  static const resampleHz = 20;

  /// FFT window length in samples (power of two, required by the radix-2
  /// FFT below). 128 samples @ 20 Hz = 6.4 s of signal -- long enough to
  /// resolve the 0.5 Hz locomotor-band edge (frequency resolution =
  /// 20/128 = 0.15625 Hz).
  static const windowSize = 128;

  static const _windowDurationMs = windowSize * 1000 ~/ resampleHz;

  /// Re-run the FFT analysis at most this often, independent of how fast
  /// pressure samples arrive over BLE.
  static const _evalIntervalMs = 400;

  static const _locomotorBandHz = (0.5, 3.0);
  static const _freezeBandHz = (3.0, 8.0);

  /// Freeze index above which an episode is considered to have started.
  /// Bachlin et al. used ~2.5 on shank-accelerometer data; kept as a named
  /// constant here since it's the main thing to recalibrate per-hardware.
  static const freezeIndexThresholdOn = 2.5;

  /// Freeze index must drop below this (hysteresis, lower than the "on"
  /// threshold) before an open episode is considered to have ended --
  /// avoids an episode flickering open/closed from noise right at the
  /// boundary.
  static const freezeIndexThresholdOff = 1.5;

  /// Minimum oscillation amplitude (squared) the loaded/unloaded pressure
  /// signal must have, across the whole locomotor+freeze band, before the
  /// window is treated as "attempting to move" at all. This is converted
  /// via Parseval's theorem from raw FFT-bin power back into the original
  /// pressure signal's units, so it's directly comparable to
  /// [ClinicalGaitAnalysis.contactThreshold] -- e.g. the default of 100
  /// means the combined signal must swing by about +/-10 pressure units
  /// somewhere in that band. Below this floor, a high freeze-index ratio
  /// is meaningless noise from a near-flat signal (standing still,
  /// insoles off) rather than an actual freeze, so it's never flagged.
  final double noiseFloor;

  final List<(int, double)> _samples = [];
  int _lastEvalMs = -1 << 30;
  FogEvent? _openEvent;
  double _openPeakFreezeIndex = 0;

  bool isFreezing = false;
  final List<FogEvent> events = [];

  /// Called once per completed episode (on close), so the caller can
  /// persist/alert on it without polling [events] every frame.
  void Function(FogEvent event)? onEvent;

  FreezeIndexDetector({this.noiseFloor = 100});

  /// Feed one new pressure sample: [timeMs] is elapsed session time, and
  /// [value] is this frame's total pressure (sum across all sensor cells,
  /// both feet) -- the vertical-loading proxy this detector analyzes.
  void push(int timeMs, num value) {
    _samples.add((timeMs, value.toDouble()));

    final cutoff = timeMs - _windowDurationMs * 2;
    _samples.removeWhere((s) => s.$1 < cutoff);

    if (_samples.length < 4) return;
    if (timeMs - _lastEvalMs < _evalIntervalMs) return;
    if (timeMs - _samples.first.$1 < _windowDurationMs) return;
    _lastEvalMs = timeMs;

    _evaluate(timeMs);
  }

  void _evaluate(int nowMs) {
    final windowed = _resampleWindow(nowMs);
    final re = List<double>.generate(windowSize, (i) => windowed[i] * _hann(i));
    final im = List<double>.filled(windowSize, 0);

    _fft(re, im);

    final df = resampleHz / windowSize;
    final locomotorPower = _bandPower(re, im, df, _locomotorBandHz);
    final freezePower = _bandPower(re, im, df, _freezeBandHz);

    // Parseval: sum(|x[n]|^2) == (1/N) * sum(|X[k]|^2) for the unnormalized
    // DFT above, and a single sinusoid of amplitude A contributes
    // (A*N/2)^2 to its bin -- so (rawBandPower * 4 / N^2) recovers an
    // amplitude-squared estimate in the original signal's units.
    final amplitudeSquaredEst = (locomotorPower + freezePower) * 4 / (windowSize * windowSize);

    final freezeIndex = locomotorPower > 1e-9 ? freezePower / locomotorPower : 0.0;
    final moving = amplitudeSquaredEst > noiseFloor;

    if (_openEvent == null) {
      if (moving && freezeIndex > freezeIndexThresholdOn) {
        _openEvent = FogEvent(startMs: nowMs, endMs: nowMs, peakFreezeIndex: freezeIndex);
        _openPeakFreezeIndex = freezeIndex;
        isFreezing = true;
      }
    } else {
      if (freezeIndex > _openPeakFreezeIndex) _openPeakFreezeIndex = freezeIndex;

      if (!moving || freezeIndex < freezeIndexThresholdOff) {
        final closed = FogEvent(
          startMs: _openEvent!.startMs,
          endMs: nowMs,
          peakFreezeIndex: _openPeakFreezeIndex,
        );
        events.add(closed);
        _openEvent = null;
        isFreezing = false;
        onEvent?.call(closed);
      }
    }
  }

  /// Linearly interpolates the irregularly-timed samples in the current
  /// window onto [windowSize] evenly-spaced points ending at [nowMs] --
  /// BLE notifications don't arrive at a perfectly fixed rate, but the FFT
  /// requires uniform sampling.
  List<double> _resampleWindow(int nowMs) {
    final startMs = nowMs - _windowDurationMs;
    final stepMs = _windowDurationMs / windowSize;
    final out = List<double>.filled(windowSize, 0);

    var j = 0;
    for (var i = 0; i < windowSize; i++) {
      final t = startMs + i * stepMs;
      while (j + 1 < _samples.length && _samples[j + 1].$1 < t) {
        j++;
      }
      if (j + 1 >= _samples.length) {
        out[i] = _samples.last.$2;
        continue;
      }
      final a = _samples[j];
      final b = _samples[j + 1];
      final span = b.$1 - a.$1;
      final frac = span > 0 ? (t - a.$1) / span : 0.0;
      out[i] = a.$2 + (b.$2 - a.$2) * frac;
    }
    return out;
  }

  static double _hann(int i) => 0.5 - 0.5 * math.cos(2 * math.pi * i / (windowSize - 1));

  static double _bandPower(
    List<double> re,
    List<double> im,
    double df,
    (double, double) bandHz,
  ) {
    // `num.clamp` returns `num` even for an int receiver, so it needs an
    // explicit `.toInt()` back before being used as a List index below.
    final loBin = (bandHz.$1 / df).round().clamp(1, windowSize ~/ 2).toInt();
    final hiBin = (bandHz.$2 / df).round().clamp(1, windowSize ~/ 2).toInt();
    var sum = 0.0;
    for (var k = loBin; k <= hiBin; k++) {
      sum += re[k] * re[k] + im[k] * im[k];
    }
    return sum;
  }

  /// In-place iterative radix-2 Cooley-Tukey FFT. `re`/`im` length must be
  /// a power of two (enforced by [windowSize]).
  static void _fft(List<double> re, List<double> im) {
    final n = re.length;
    for (var i = 1, j = 0; i < n; i++) {
      var bit = n >> 1;
      for (; j & bit != 0; bit >>= 1) {
        j ^= bit;
      }
      j ^= bit;
      if (i < j) {
        var tmp = re[i];
        re[i] = re[j];
        re[j] = tmp;
        tmp = im[i];
        im[i] = im[j];
        im[j] = tmp;
      }
    }

    for (var len = 2; len <= n; len <<= 1) {
      final ang = -2 * math.pi / len;
      final wReal = math.cos(ang);
      final wImag = math.sin(ang);
      for (var i = 0; i < n; i += len) {
        var curReal = 1.0;
        var curImag = 0.0;
        for (var k = 0; k < len ~/ 2; k++) {
          final uRe = re[i + k];
          final uIm = im[i + k];
          final vRe = re[i + k + len ~/ 2] * curReal - im[i + k + len ~/ 2] * curImag;
          final vIm = re[i + k + len ~/ 2] * curImag + im[i + k + len ~/ 2] * curReal;

          re[i + k] = uRe + vRe;
          im[i + k] = uIm + vIm;
          re[i + k + len ~/ 2] = uRe - vRe;
          im[i + k + len ~/ 2] = uIm - vIm;

          final nextReal = curReal * wReal - curImag * wImag;
          final nextImag = curReal * wImag + curImag * wReal;
          curReal = nextReal;
          curImag = nextImag;
        }
      }
    }
  }

  void reset() {
    _samples.clear();
    _lastEvalMs = -1 << 30;
    _openEvent = null;
    _openPeakFreezeIndex = 0;
    isFreezing = false;
    events.clear();
  }
}
