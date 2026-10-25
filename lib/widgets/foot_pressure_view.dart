import 'package:flutter/material.dart';

import '../models/foot_point_layout.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Renders one foot's live/replayed pressure grid, either as a heatmap
/// (mirrors `components/insole/Heat/Heat.vue` + `RHeat.vue`) or as discrete
/// point indicators (mirrors `LeftColor.vue` / `RightColor.vue`).
///
/// Deliberately has no drawn foot silhouette/boundary -- matching a real
/// plantar-pressure scanner display, the "foot shape" comes entirely from
/// where the actual sensors are and how much pressure they're reading,
/// not an artificial outline. At rest, each of the 16 sensor positions
/// shows as a small neutral dot in its real physical layout; the moment
/// real pressure appears, colored blobs bloom at the loaded sensors and
/// merge into a foot-shaped region purely because that's where the
/// sensors physically are.
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
  final Color zeroDotColor;

  _FootPainter({
    required this.points,
    required this.colOffset,
    required this.values,
    required this.heatMode,
    required this.zeroDotColor,
  });

  Offset _pointPos(Size size, int row, int col) {
    final x = (col - colOffset) / FootPointLayout.maxCol;
    // Row 0 is the forefoot (toes), row 19 is the heel, and the widget's
    // y axis already runs top-to-bottom in that same order (py below maps
    // y=0 to the top, y=1 to the bottom) -- so this is a direct mapping,
    // NOT inverted. (A previous `1 - ...` here was backwards: it put the
    // heel at the top and toes at the bottom.)
    final y = (row - FootPointLayout.minRow) / FootPointLayout.maxRow;
    // Keep points comfortably inside the widget's bounds.
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
    const maxValue = 30.0; // scaled sensor units (post threshold+scale)

    // No silhouette, no clip, no base fill: the "foot shape" is whatever
    // the real sensor data draws, nothing more. At rest, a small neutral
    // dot marks each of the 16 real sensor positions (in their true
    // physical layout) so the sensors still read as present/live; the
    // moment a point has real pressure, a soft colored blob replaces its
    // dot, and overlapping blobs from neighboring loaded sensors merge
    // into a continuous foot-shaped region purely because that's where
    // the sensors physically sit underfoot.
    // Painted lowest-value first, so a higher-pressure point's blob is
    // never visually dulled by a lower one's semi-transparent edge
    // landing on top of it afterward.
    final order = List<int>.generate(points.length, (i) => i)
      ..sort((a, b) => values[a].compareTo(values[b]));

    for (final i in order) {
      final v = values[i];
      final pos = _pointPos(size, points[i][0], points[i][1]);

      if (v <= 0) {
        canvas.drawCircle(pos, size.width * 0.02, Paint()..color = zeroDotColor.withValues(alpha: 0.3));
        continue;
      }

      final t = (v / maxValue).clamp(0.0, 1.0);

      if (heatMode) {
        // Large, overlapping radii spread each hot spot into its
        // surroundings so neighboring loaded sensors read as one smooth
        // gradient rather than separate dots.
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
      } else {
        final radius = size.width * (0.05 + 0.05 * t);
        canvas.drawCircle(pos, radius, Paint()..color = _rampColor(t));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FootPainter oldDelegate) {
    return heatMode != oldDelegate.heatMode ||
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
