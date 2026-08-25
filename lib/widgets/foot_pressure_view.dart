import 'package:flutter/material.dart';

import '../models/foot_point_layout.dart';
import '../theme/app_colors.dart';

/// Renders one foot's live/replayed pressure grid, either as a heatmap
/// (mirrors `components/insole/Heat/Heat.vue` + `RHeat.vue`) or as discrete
/// point indicators (mirrors `LeftColor.vue` / `RightColor.vue`).
///
/// There's no foot-outline artwork bundled with this port (the original
/// app's `/static/img/left.png` / `right.png` weren't shared), so the
/// silhouette is drawn procedurally -- swap `_FootOutlinePainter` for an
/// `Image.asset` + mask if you have the real artwork.
class FootPressureView extends StatelessWidget {
  final List<List<int>> grid;
  final bool isRight;
  final bool heatMode;
  final double width;
  final double height;

  const FootPressureView({
    super.key,
    required this.grid,
    required this.isRight,
    this.heatMode = true,
    this.width = 140,
    this.height = 320,
  });

  @override
  Widget build(BuildContext context) {
    final points = isRight ? FootPointLayout.right : FootPointLayout.left;
    final colOffset = isRight ? 10 : 0;

    final values = points
        .map((rc) => grid[rc[0]][rc[1]])
        .toList(growable: false);

    return SizedBox(
      width: width,
      height: height,
      child: CustomPaint(
        painter: _FootPainter(
          points: points,
          colOffset: colOffset,
          values: values,
          heatMode: heatMode,
        ),
      ),
    );
  }
}

class _FootPainter extends CustomPainter {
  final List<List<int>> points;
  final int colOffset;
  final List<int> values;
  final bool heatMode;

  _FootPainter({
    required this.points,
    required this.colOffset,
    required this.values,
    required this.heatMode,
  });

  Path _outline(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    // A simple stylized foot silhouette in a 0..1 x 0..1 box, toes at top.
    path.moveTo(w * 0.50, h * 0.02);
    path.cubicTo(w * 0.68, h * 0.02, w * 0.80, h * 0.10, w * 0.78, h * 0.20);
    path.cubicTo(w * 0.76, h * 0.28, w * 0.66, h * 0.30, w * 0.66, h * 0.38);
    path.cubicTo(w * 0.66, h * 0.46, w * 0.92, h * 0.55, w * 0.94, h * 0.72);
    path.cubicTo(w * 0.97, h * 0.88, w * 0.80, h * 0.99, w * 0.50, h * 0.99);
    path.cubicTo(w * 0.20, h * 0.99, w * 0.03, h * 0.88, w * 0.06, h * 0.72);
    path.cubicTo(w * 0.08, h * 0.55, w * 0.34, h * 0.46, w * 0.34, h * 0.38);
    path.cubicTo(w * 0.34, h * 0.30, w * 0.24, h * 0.28, w * 0.22, h * 0.20);
    path.cubicTo(w * 0.20, h * 0.10, w * 0.32, h * 0.02, w * 0.50, h * 0.02);
    path.close();
    return path;
  }

  Offset _pointPos(Size size, int row, int col) {
    final x = (col - colOffset) / FootPointLayout.maxCol;
    final y = (row - FootPointLayout.minRow) / FootPointLayout.maxRow;
    // Keep points comfortably inside the silhouette.
    final margin = size.width * 0.12;
    final px = margin + x * (size.width - margin * 2);
    final py = size.height * 0.06 + y * (size.height * 0.88);
    return Offset(px, py);
  }

  Color _rampColor(double t) {
    final ramp = AppColors.heatRamp;
    final clamped = t.clamp(0.0, 1.0);
    final scaled = clamped * (ramp.length - 1);
    final i = scaled.floor().clamp(0, ramp.length - 2);
    final frac = scaled - i;
    return Color.lerp(ramp[i], ramp[i + 1], frac)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final outline = _outline(size);

    final outlineFill = Paint()
      ..color = AppColors.surface2
      ..style = PaintingStyle.fill;
    final outlineStroke = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(outline, outlineFill);
    canvas.drawPath(outline, outlineStroke);

    canvas.save();
    canvas.clipPath(outline);

    const maxValue = 30.0; // scaled sensor units (post threshold+scale)

    if (heatMode) {
      for (var i = 0; i < points.length; i++) {
        final v = values[i];
        if (v <= 0) continue;
        final pos = _pointPos(size, points[i][0], points[i][1]);
        final t = (v / maxValue).clamp(0.0, 1.0);
        final radius = size.width * (0.16 + 0.14 * t);

        final gradient = RadialGradient(
          colors: [
            _rampColor(t).withValues(alpha: 0.9),
            _rampColor(t).withValues(alpha: 0.0),
          ],
        );
        final rect = Rect.fromCircle(center: pos, radius: radius);
        final paint = Paint()..shader = gradient.createShader(rect);
        canvas.drawCircle(pos, radius, paint);
      }
    } else {
      for (var i = 0; i < points.length; i++) {
        final v = values[i];
        final pos = _pointPos(size, points[i][0], points[i][1]);
        final t = (v / maxValue).clamp(0.0, 1.0);

        final dotPaint = Paint()
          ..color = v > 0 ? _rampColor(t) : AppColors.textTertiary.withValues(alpha: 0.35);
        final radius = v > 0 ? size.width * (0.05 + 0.05 * t) : size.width * 0.025;
        canvas.drawCircle(pos, radius, dotPaint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FootPainter oldDelegate) {
    return heatMode != oldDelegate.heatMode ||
        !_listEquals(values, oldDelegate.values);
  }

  bool _listEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
