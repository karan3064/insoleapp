import 'package:flutter/material.dart';

/// The NurvoSync brand mark: a sync ring with a pulse/heartbeat line
/// through the center and an accent "ping" dot at the peak. Same glyph
/// used for the app icon (see assets/icon/), redrawn as a widget so it
/// stays crisp at any size and can pick up the app's live theme.
class NurvoSyncMark extends StatelessWidget {
  final double size;
  final Color ringColor;
  final Color pulseColor;

  const NurvoSyncMark({
    super.key,
    this.size = 72,
    this.ringColor = Colors.white,
    this.pulseColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _MarkPainter(ringColor: ringColor, pulseColor: pulseColor),
      ),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final Color ringColor;
  final Color pulseColor;

  _MarkPainter({required this.ringColor, required this.pulseColor});

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 200;
    final center = Offset(size.width / 2, size.height / 2);

    final ringPaint = Paint()
      ..color = ringColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10 * scale
      ..strokeCap = StrokeCap.round;

    // Ring with a small open gap (suggests motion/syncing), matching the
    // app icon's SVG: stroke-dasharray "290 352" on a r=56 circle (whose
    // circumference is ~351.86, i.e. close to the "352" gap value, so the
    // dash covers 290/circumference of the ring), dashoffset -16, rotated
    // -90deg so the pattern starts at the top.
    const refRadius = 56.0;
    const circumference = 2 * 3.14159265 * refRadius;
    const dashFraction = 290 / circumference;
    const offsetFraction = 16 / circumference;
    const startAngle = -3.14159265 / 2 - offsetFraction * 2 * 3.14159265;
    const sweepAngle = dashFraction * 2 * 3.14159265;

    final radius = refRadius * scale;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, startAngle, sweepAngle, false, ringPaint);

    final pulsePaint = Paint()
      ..color = pulseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9 * scale
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    Offset pt(double x, double y) => Offset(x * scale, y * scale);

    final path = Path()
      ..moveTo(pt(34, 100).dx, pt(34, 100).dy)
      ..lineTo(pt(72, 100).dx, pt(72, 100).dy)
      ..lineTo(pt(84, 64).dx, pt(84, 64).dy)
      ..lineTo(pt(102, 138).dx, pt(102, 138).dy)
      ..lineTo(pt(116, 80).dx, pt(116, 80).dy)
      ..lineTo(pt(126, 100).dx, pt(126, 100).dy)
      ..lineTo(pt(166, 100).dx, pt(166, 100).dy);
    canvas.drawPath(path, pulsePaint);

    final dotPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(-0.3, -0.3),
        colors: [Color(0xFFFDBA74), Color(0xFFF97316)],
      ).createShader(Rect.fromCircle(center: pt(102, 138), radius: 9 * scale));
    canvas.drawCircle(pt(102, 138), 9 * scale, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _MarkPainter oldDelegate) {
    return ringColor != oldDelegate.ringColor || pulseColor != oldDelegate.pulseColor;
  }
}
