/// One detected Freezing-of-Gait episode, from [FreezeIndexDetector].
class FogEvent {
  /// Elapsed session time (ms) when the episode began.
  final int startMs;

  /// Elapsed session time (ms) when the pressure signal exited the
  /// freeze-band-dominant state again.
  final int endMs;

  /// Highest freeze index (freeze-band power / locomotor-band power)
  /// observed while this episode was open.
  final double peakFreezeIndex;

  const FogEvent({
    required this.startMs,
    required this.endMs,
    required this.peakFreezeIndex,
  });

  int get durationMs => endMs - startMs;

  Map<String, dynamic> toJson() => {
        'startMs': startMs,
        'endMs': endMs,
        'peakFreezeIndex': peakFreezeIndex,
      };

  factory FogEvent.fromJson(Map<String, dynamic> json) => FogEvent(
        startMs: (json['startMs'] as num).toInt(),
        endMs: (json['endMs'] as num).toInt(),
        peakFreezeIndex: (json['peakFreezeIndex'] as num).toDouble(),
      );
}
