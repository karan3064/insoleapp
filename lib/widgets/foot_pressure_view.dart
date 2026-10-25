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
    // Row 0 is the forefoot (toes), row 19 is the heel, and the widget's
    // y axis already runs top-to-bottom in that same order (py below maps
    // y=0 to the top, y=1 to the bottom) -- so this is a direct mapping,
    // NOT inverted. (A previous `1 - ...` here was backwards: it put the
    // heel at the top and toes at the bottom.)
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
      // A continuous-looking clinical pressure map (like the reference jet
      // colormap) needs the whole foot colored, not just hot spots over a
      // blank background. Rather than blend overlapping colors via a
      // custom BlendMode (BlendMode.plus washes out to white wherever
      // several blobs overlap; BlendMode.lighten does a per-channel max
      // that mixes hues into muddy off-ramp colors, e.g. cyan+red ->
      // pink) -- both unpredictable without being able to see the actual
      // render -- this fills the whole outline with the coldest ramp
      // color first, then layers ordinary alpha-blended hot-spot blobs on
      // top, painter's-algorithm style, hottest last. Normal source-over
      // compositing of a known base + known overlays stays predictable.
      final basePaint = Paint()..color = _rampColor(0);
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), basePaint);

      final order = List<int>.generate(points.length, (i) => i)
        ..sort((a, b) => values[a].compareTo(values[b]));

      for (final i in order) {
        final v = values[i];
        if (v <= 0) continue;
        final pos = _pointPos(size, points[i][0], points[i][1]);
        final t = (v / maxValue).clamp(0.0, 1.0);
        // Large, overlapping radii spread each hot spot into its
        // surroundings so neighboring points read as one smooth gradient
        // rather than separate dots.
        final radius = size.width * (0.30 + 0.16 * t);

        // A flat-then-fading falloff (full color held out to 40% of the
        // radius, then fading) reads as a soft blur, closer to a real
        // interpolated pressure map, instead of a hard-centered dot that
        // immediately starts fading from the very center.
        final color = _rampColor(t);
        final gradient = RadialGradient(
          colors: [color, color, color.withValues(alpha: 0.0)],
          stops: const [0.0, 0.4, 1.0],
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
