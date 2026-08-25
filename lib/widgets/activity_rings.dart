import 'dart:math';

import 'package:flutter/material.dart';

class RingSpec {
  final double percent; // 0-100
  final Color color;
  final Color trackColor;

  const RingSpec({required this.percent, required this.color, required this.trackColor});
}

/// Apple-Watch-style concentric progress rings, mirroring
/// `components/ActivityRings/ActivityRings.vue`.
class ActivityRings extends StatelessWidget {
  final List<RingSpec> rings;
  final double size;
  final double strokeWidth;
  final double gap;
  final Widget? center;

  const ActivityRings({
    super.key,
    required this.rings,
    this.size = 220,
    this.strokeWidth = 18,
    this.gap = 6,
    this.center,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) {
              return CustomPaint(
                size: Size(size, size),
                painter: _RingsPainter(
                  rings: rings,
                  progress: t,
                  strokeWidth: strokeWidth,
                  gap: gap,
                ),
              );
            },
          ),
          if (center != null) center!,
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  final List<RingSpec> rings;
  final double progress;
  final double strokeWidth;
  final double gap;

  _RingsPainter({
    required this.rings,
    required this.progress,
    required this.strokeWidth,
    required this.gap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    var radius = size.width / 2;

    for (final ring in rings) {
      final trackPaint = Paint()
        ..color = ring.trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final activePaint = Paint()
        ..color = ring.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      final center = Offset(size.width / 2, size.height / 2);
      final ringRadius = radius - strokeWidth / 2;
      final rect = Rect.fromCircle(center: center, radius: ringRadius);

      canvas.drawArc(rect, 0, 2 * pi, false, trackPaint);

      final sweep = 2 * pi * (ring.percent.clamp(0, 100) / 100) * progress;
      canvas.drawArc(rect, -pi / 2, sweep, false, activePaint);

      radius -= strokeWidth + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _RingsPainter oldDelegate) {
    return progress != oldDelegate.progress || rings != oldDelegate.rings;
  }
}
