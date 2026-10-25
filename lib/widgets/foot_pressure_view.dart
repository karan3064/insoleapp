import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/foot_point_layout.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Renders one foot's live/replayed pressure grid, either as a heatmap
/// (mirrors `components/insole/Heat/Heat.vue` + `RHeat.vue`) or as discrete
/// point indicators (mirrors `LeftColor.vue` / `RightColor.vue`).
///
/// There's no foot-outline artwork bundled with this port (the original
/// app's `/static/img/left.png` / `right.png` weren't shared), so the
/// silhouette is drawn procedurally -- swap `_FootOutlinePainter` for an
/// `Image.asset` + mask if you have the real artwork. A sensor-data-only
/// render (no drawn boundary at all) was tried and reverted: with only
/// 16 sparse sensors per foot, the two feet read as one scattered mess of
/// dots without an outline to tell them apart -- real commercial scanners
/// that get away with no boundary have hundreds of sensors.
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
    final p = context.palette;

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
          outlineFillColor: p.surface2,
          outlineBorderColor: p.border,
          zeroDotColor: p.textTertiary,
        ),
      ),
    );
  }
}

/// The vertical color-scale bar shown alongside a heatmap (matches the
/// legend on commercial plantar-pressure scanners): hottest color at top,
/// coldest at bottom, with endpoint labels.
class HeatLegend extends StatelessWidget {
  final double height;
  const HeatLegend({super.key, this.height = 260});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Text('High', style: TextStyle(fontSize: 10, color: p.textSecondary)),
          const SizedBox(height: 4),
          Expanded(
            child: Container(
              width: 14,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: AppColors.heatRamp.reversed.toList(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text('Low', style: TextStyle(fontSize: 10, color: p.textSecondary)),
        ],
      ),
    );
  }
}

class _FootPainter extends CustomPainter {
  final List<List<int>> points;
  final int colOffset;
  final List<int> values;
  final bool heatMode;
  final Color outlineFillColor;
  final Color outlineBorderColor;
  final Color zeroDotColor;

  _FootPainter({
    required this.points,
    required this.colOffset,
    required this.values,
    required this.heatMode,
    required this.outlineFillColor,
    required this.outlineBorderColor,
    required this.zeroDotColor,
  });

  Path _outline(Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path();
    // Every h-coordinate below is `1 - Y` of the original hand-authored
    // silhouette (each term checked individually: e.g. original h*0.02 ->
    // h*0.98, h*0.72 -> h*0.28, etc.) -- the original had its wide curve
    // (forefoot/toes) at the BOTTOM and its narrow curve (heel) at the
    // TOP, backwards from _pointPos's toes-at-top mapping (confirmed
    // correct against real sensor data on-device). Toes at top now.
    path.moveTo(w * 0.50, h * 0.98);
    path.cubicTo(w * 0.68, h * 0.98, w * 0.80, h * 0.90, w * 0.78, h * 0.80);
    path.cubicTo(w * 0.76, h * 0.72, w * 0.66, h * 0.70, w * 0.66, h * 0.62);
    path.cubicTo(w * 0.66, h * 0.54, w * 0.92, h * 0.45, w * 0.94, h * 0.28);
    path.cubicTo(w * 0.97, h * 0.12, w * 0.80, h * 0.01, w * 0.50, h * 0.01);
    path.cubicTo(w * 0.20, h * 0.01, w * 0.03, h * 0.12, w * 0.06, h * 0.28);
    path.cubicTo(w * 0.08, h * 0.45, w * 0.34, h * 0.54, w * 0.34, h * 0.62);
    path.cubicTo(w * 0.34, h * 0.70, w * 0.24, h * 0.72, w * 0.22, h * 0.80);
    path.cubicTo(w * 0.20, h * 0.90, w * 0.32, h * 0.98, w * 0.50, h * 0.98);
    path.close();
    return path;
  }

  Offset _pointPos(Size size, int row, int col) {
    final x = (col - colOffset) / FootPointLayout.maxCol;
    // Row 0 is the forefoot (toes), row 19 is the heel, and the widget's
    // y axis already runs top-to-bottom in that same order (py below maps
    // y=0 to the top, y=1 to the bottom) -- so this is a direct mapping,
    // NOT inverted.
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
      ..color = outlineFillColor
      ..style = PaintingStyle.fill;
    final outlineStroke = Paint()
      ..color = outlineBorderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    canvas.drawPath(outline, outlineFill);
    canvas.drawPath(outline, outlineStroke);

    canvas.save();
    canvas.clipPath(outline);

    const maxValue = 30.0; // scaled sensor units (post threshold+scale)

    if (heatMode) {
      // A continuous-looking clinical pressure map needs the whole foot
      // colored, not just hot spots over a blank background -- fill the
      // whole outline with the coldest ramp color first, then layer
      // hot-spot blobs on top, hottest last.
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), Paint()..color = _rampColor(0));

      final order = List<int>.generate(points.length, (i) => i)
        ..sort((a, b) => values[a].compareTo(values[b]));

      for (final i in order) {
        final v = values[i];
        if (v <= 0) continue;
        final pos = _pointPos(size, points[i][0], points[i][1]);
        final t = (v / maxValue).clamp(0.0, 1.0);

        // A real Gaussian blur (not a radial-gradient alpha fade) is what
        // makes neighboring hot spots melt into one continuous blob
        // instead of reading as a cluster of distinct overlapping
        // circles -- a gradient's edge, however soft, is still a crisp
        // boundary once two of them overlap at the same alpha; a blur
        // genuinely diffuses the pixels themselves.
        final radius = size.width * (0.22 + 0.12 * t);
        final paint = Paint()
          ..color = _rampColor(t)
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, radius * 0.6);
        canvas.drawCircle(pos, radius, paint);
      }
    } else {
      for (var i = 0; i < points.length; i++) {
        final v = values[i];
        final pos = _pointPos(size, points[i][0], points[i][1]);
        final t = (v / maxValue).clamp(0.0, 1.0);

        final dotPaint = Paint()
          ..color = v > 0 ? _rampColor(t) : zeroDotColor.withValues(alpha: 0.35);
        final radius = v > 0 ? size.width * (0.05 + 0.05 * t) : size.width * 0.025;
        canvas.drawCircle(pos, radius, dotPaint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FootPainter oldDelegate) {
    return heatMode != oldDelegate.heatMode ||
        outlineFillColor != oldDelegate.outlineFillColor ||
        outlineBorderColor != oldDelegate.outlineBorderColor ||
        zeroDotColor != oldDelegate.zeroDotColor ||
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
