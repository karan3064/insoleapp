import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/record_summary.dart';
import '../services/ai_narrative_service.dart';
import '../services/ensemble_gait_screening.dart';
import '../services/format_utils.dart';
import '../state/auth_provider.dart';
import '../state/ble_provider.dart';
import '../state/insole_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/foot_line_chart.dart';
import '../widgets/foot_pressure_view.dart';
import '../widgets/gps_path_map.dart';
import 'detail_screen.dart';

/// Mirrors `chart/gather/gather.vue`: live point/heat view toggle, GPS path
/// map, start/stop test controls, and per-foot pressure line charts.
class GatherScreen extends StatefulWidget {
  const GatherScreen({super.key});

  @override
  State<GatherScreen> createState() => _GatherScreenState();
}

class _GatherScreenState extends State<GatherScreen> {
  bool _heatMode = true;
  bool _saving = false;

  /// Snapshots the session captured so far into a saved record. Capture
  /// keeps running uninterrupted afterwards -- both insoles stay connected
  /// and data keeps accumulating for the next one, so there's no
  /// reconnect step between sessions.
  Future<void> _saveSession() async {
    setState(() => _saving = true);

    final ble = context.read<BleProvider>();
    final insole = context.read<InsoleProvider>();
    final auth = context.read<AuthProvider>();

    final deviceName = ble.connectedDevices.isNotEmpty ? ble.connectedDevices.first.name : 'Insole';
    final record = await ble.saveSession(insole.nextId, deviceName);

    await insole.saveRecord(record);
    unawaited(insole.syncRecord(auth.uid, record));

    if (!mounted) return;
    setState(() => _saving = false);

    // Capstone moment: surface the AI's plain-language read of the walk
    // just finished, front and center, before anything else -- not
    // buried a tap away on the detail screen.
    final ensemble = EnsembleGaitScreening.evaluate(
      gait: record.summary.clinical,
      speedMps: null,
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AiSummarySheet(summary: record.summary, ensemble: ensemble),
    );

    if (!mounted) return;
    // Pushed (not replaced) so the back button returns here, still
    // connected and still capturing.
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DetailScreen(recordId: record.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Test')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: p.card(),
              child: Column(
                children: [
                  _ModeToggle(
                    heatMode: _heatMode,
                    onChanged: (v) => setState(() => _heatMode = v),
                  ),
                  const SizedBox(height: 16),
                  // Horizontally scrollable as a hard guard against overflow --
                  // the legend + two foot widgets' combined width doesn't fit
                  // every phone's screen width, and a RenderFlex overflow
                  // (the yellow/black hazard stripe) is worse than a view
                  // that's occasionally scrollable on narrow devices.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (_heatMode) ...[const HeatLegend(), const SizedBox(width: 12)],
                        FootPressureView(grid: ble.grid, isRight: false, heatMode: _heatMode),
                        const SizedBox(width: 12),
                        FootPressureView(grid: ble.grid, isRight: true, heatMode: _heatMode),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ble.isCapturing ? AppColors.success : p.textTertiary,
                        ),
                      ),
                      Text(
                        ble.isCapturing
                            ? 'Recording ${FormatUtils.secondsToMinutesString(ble.elapsedSeconds)}'
                            : 'Not connected',
                        style: TextStyle(color: p.textSecondary),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (ble.isCapturing) ...[
              const SizedBox(height: 12),
              _LiveAiMonitorBar(
                isFreezing: ble.isFreezing,
                isCueingActive: ble.isCueingActive,
                freezeHistory: ble.freezeIndexHistory,
                liveEnsemble: ble.liveEnsemble,
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: ble.isCapturing && !_saving ? _saveSession : null,
              child: Text(_saving ? 'Saving...' : 'Save session'),
            ),
            const SizedBox(height: 20),
            if (ble.path.isNotEmpty) GpsPathMap(path: ble.path),
            const SizedBox(height: 20),
            const Text('Left foot waveform', style: TextStyle(fontWeight: FontWeight.w700)),
            FootLineChart(data: ble.leftLine),
            const SizedBox(height: 20),
            const Text('Right foot waveform', style: TextStyle(fontWeight: FontWeight.w700)),
            FootLineChart(data: ble.rightLine),
          ],
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final bool heatMode;
  final ValueChanged<bool> onChanged;

  const _ModeToggle({required this.heatMode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    Widget segment(String label, bool active, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: active ? AppColors.primary : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: active ? AppColors.onPrimary : p.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: p.bg,
        border: Border.all(color: p.border),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          segment('Points', !heatMode, () => onChanged(false)),
          segment('Heat', heatMode, () => onChanged(true)),
        ],
      ),
    );
  }
}

/// Always visible while a test is actively capturing -- answers "what AI
/// is actually running while I'm wearing the insoles", not just "what AI
/// ran after I save the session". `FreezeIndexDetector` (frequency-domain
/// signal analysis), the live ensemble-screening re-check, and the
/// rhythmic-cueing response all genuinely run on the live pressure stream
/// already; this just surfaces that honestly, with the actual freeze-index
/// signal plotted live and the two screening models' live agreement state,
/// instead of only showing anything when a freeze actually fires.
class _LiveAiMonitorBar extends StatelessWidget {
  final bool isFreezing;
  final bool isCueingActive;
  final List<double> freezeHistory;
  final EnsembleGaitScreeningResult? liveEnsemble;

  const _LiveAiMonitorBar({
    required this.isFreezing,
    required this.isCueingActive,
    required this.freezeHistory,
    required this.liveEnsemble,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = isFreezing ? AppColors.warning : AppColors.primary;
    final String text;
    if (isFreezing) {
      text = isCueingActive
          ? 'Possible freeze detected -- rhythmic pulse cueing active to help you keep walking'
          : 'Possible freezing-of-gait signal detected';
    } else {
      text = 'AI monitoring active -- analyzing freeze-of-gait signal in real time';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: isFreezing ? 1.0 : 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isFreezing ? Icons.warning_amber_rounded : Icons.auto_awesome,
                color: color,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
              ),
              if (isCueingActive) Icon(Icons.vibration, color: color),
            ],
          ),
          if (freezeHistory.length >= 2) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  'Freeze-index signal',
                  style: TextStyle(color: p.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  freezeHistory.last.toStringAsFixed(2),
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 36,
              width: double.infinity,
              child: CustomPaint(
                painter: _FreezeSparklinePainter(values: freezeHistory, lineColor: color),
              ),
            ),
          ],
          const SizedBox(height: 10),
          _LiveEnsembleBadge(ensemble: liveEnsemble),
        ],
      ),
    );
  }
}

/// Live analogue of `DetailScreen`'s `_GaitScreeningCard` badge -- same
/// "2 models agree" / "Models disagree" language, but re-computed every
/// few seconds from the session-so-far's data (see
/// `BleProvider._updateLiveEnsemble`) instead of once at save time, so the
/// jury sees the two AI judges actually checking each other live, not just
/// a claim made after the fact.
class _LiveEnsembleBadge extends StatelessWidget {
  final EnsembleGaitScreeningResult? ensemble;
  const _LiveEnsembleBadge({required this.ensemble});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final e = ensemble;

    final String label;
    final Color color;
    final IconData icon;
    if (e == null || e.agreement == EnsembleAgreement.insufficientData) {
      label = 'Two screening models warming up...';
      color = p.textTertiary;
      icon = Icons.hourglass_top_rounded;
    } else if (e.agreement == EnsembleAgreement.agree) {
      label = 'Logistic regression + random forest agree';
      color = AppColors.success;
      icon = Icons.check_circle;
    } else {
      label = 'Models disagree -- flagged inconclusive, not guessed';
      color = AppColors.warning;
      icon = Icons.rule;
    }

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Minimal hand-rolled line sparkline -- no charting package needed for a
/// handful of points redrawn every ~400ms. Draws the most recent
/// [_FreezeSparklinePainter.values] left-to-right, auto-scaled to the
/// window's own min/max rather than a fixed axis, since the freeze index's
/// useful range shifts a lot between standing still and mid-freeze.
class _FreezeSparklinePainter extends CustomPainter {
  final List<double> values;
  final Color lineColor;
  const _FreezeSparklinePainter({required this.values, required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final maxV = values.reduce(math.max);
    final minV = values.reduce(math.min);
    final span = (maxV - minV).abs() < 1e-6 ? 1.0 : (maxV - minV);

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = values.length == 1 ? 0.0 : size.width * i / (values.length - 1);
      final normalized = (values[i] - minV) / span;
      final y = size.height - (normalized * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    final linePaint = Paint()
      ..color = lineColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = lineColor;
    final lastX = size.width;
    final lastNormalized = (values.last - minV) / span;
    final lastY = size.height - (lastNormalized * size.height);
    canvas.drawCircle(Offset(lastX, lastY), 3, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _FreezeSparklinePainter oldDelegate) =>
      !identical(oldDelegate.values, values) || oldDelegate.lineColor != lineColor;
}

/// The capstone moment right after a demo walk: Gemini's plain-language
/// read of the session the user/judge just watched happen, surfaced
/// immediately and prominently -- not a tap away on the detail screen.
/// Generates on open; failure is shown inline (never silently swallowed),
/// since this runs live in front of an audience.
class _AiSummarySheet extends StatefulWidget {
  final RecordSummary summary;
  final EnsembleGaitScreeningResult ensemble;
  const _AiSummarySheet({required this.summary, required this.ensemble});

  @override
  State<_AiSummarySheet> createState() => _AiSummarySheetState();
}

class _AiSummarySheetState extends State<_AiSummarySheet> {
  String? _narrative;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    try {
      final narrative = await AiNarrativeService.generateSessionNarrative(
        summary: widget.summary,
        ensemble: widget.ensemble,
      );
      if (!mounted) return;
      setState(() {
        _narrative = narrative;
        _loading = false;
      });
    } on AiNarrativeException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final agree = widget.ensemble.agreement == EnsembleAgreement.agree;

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: p.border),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 24, offset: Offset(0, 8))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.primary, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('AI read of this walk', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ),
                if (widget.ensemble.agreement != EnsembleAgreement.insufficientData)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (agree ? AppColors.primary : AppColors.warning).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      agree ? '2 models agree' : 'Models disagree',
                      style: TextStyle(
                        color: agree ? AppColors.primary : AppColors.warning,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: const TextStyle(color: AppColors.error))
            else
              Text(
                _narrative ?? '',
                style: TextStyle(color: p.text, fontSize: 14.5, height: 1.5),
              ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('View full details'),
            ),
          ],
        ),
      ),
    );
  }
}
