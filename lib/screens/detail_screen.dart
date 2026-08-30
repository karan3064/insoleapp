import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../models/insole_record.dart';
import '../models/pressure_frame.dart';
import '../services/format_utils.dart';
import '../services/gait_analysis.dart';
import '../services/health_calc.dart';
import '../state/auth_provider.dart';
import '../state/insole_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/foot_line_chart.dart';
import '../widgets/foot_pressure_view.dart';

/// Mirrors `chart/detail/detail.vue`: replays a saved test session and
/// shows the derived gait analytics (footprint, arch, landing method,
/// cadence, ground/air time, forefoot/mid/heel touchdown split).
class DetailScreen extends StatefulWidget {
  final int recordId;

  const DetailScreen({super.key, required this.recordId});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _heatMode = true;
  bool _playing = false;
  int _playhead = 0;
  Timer? _timer;
  List<List<int>> _grid = emptyGrid();

  InsoleRecord? _record;

  static const _frontKeys = ['data', 'data2', 'data3', 'data4', 'data5', 'data6', 'data7', 'data8'];
  static const _midKeys = ['data9', 'data10', 'data11', 'data12', 'data13', 'data14'];
  static const _rearKeys = ['data15', 'data16'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _record ??= context.read<InsoleProvider>().byId(widget.recordId);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _play() {
    final record = _record;
    if (record == null || record.details.isEmpty) return;

    setState(() {
      _playing = true;
      if (_playhead >= record.time) _playhead = 0;
    });

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_playhead >= record.time) {
        _stop();
        return;
      }
      final frame = record.details.firstWhere(
        (f) => f.time == _playhead,
        orElse: () => PressureFrame(time: _playhead, item: _grid),
      );
      setState(() {
        _grid = frame.item;
        _playhead++;
      });
    });
  }

  void _stop() {
    _timer?.cancel();
    setState(() => _playing = false);
  }

  @override
  Widget build(BuildContext context) {
    final record = _record;

    final p = context.palette;

    if (record == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Test detail')),
        body: Center(child: Text('Record not found', style: TextStyle(color: p.textSecondary))),
      );
    }

    final auth = context.watch<AuthProvider>();

    final footprintResult = GaitAnalysis.footprint(record.line, record.rightLine);
    final leftProportion = GaitAnalysis.proportion(record.line);

    final calorie = HealthCalc.calculateCalories(record.distanceKm, auth.profile.weightKg);
    final target = (calorie / 5000 * 100).round();

    final stepCount = GaitAnalysis.processFrames(record.details);
    final sTarget = (stepCount / 10000 * 100).round();
    final cadence = GaitAnalysis.calculateCadence(stepCount, record.time);

    final flightContact = GaitAnalysis.analyzeFlightAndContact(
      GaitAnalysis.truncateToSevenCols(record.details),
    );

    final lFront = GaitAnalysis.calculateAverage(record.line, _frontKeys).round();
    final rFront = GaitAnalysis.calculateAverage(record.rightLine, _frontKeys).round();
    final lMid = GaitAnalysis.calculateAverage(record.line, _midKeys).round();
    final rMid = GaitAnalysis.calculateAverage(record.rightLine, _midKeys).round();
    final lRear = GaitAnalysis.calculateAverage(record.line, _rearKeys).round();
    final rRear = GaitAnalysis.calculateAverage(record.rightLine, _rearKeys).round();

    return Scaffold(
      appBar: AppBar(title: Text(record.name)),
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
                  _ModeToggle(heatMode: _heatMode, onChanged: (v) => setState(() => _heatMode = v)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      FootPressureView(grid: _grid, isRight: false, heatMode: _heatMode),
                      FootPressureView(grid: _grid, isRight: true, heatMode: _heatMode),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                            color: AppColors.primary, size: 36),
                        onPressed: record.details.isEmpty ? null : (_playing ? _stop : _play),
                      ),
                      Expanded(
                        child: Slider(
                          value: _playhead.clamp(0, record.time).toDouble(),
                          max: record.time.toDouble().clamp(1, double.infinity),
                          onChanged: (v) {
                            _stop();
                            setState(() => _playhead = v.round());
                          },
                        ),
                      ),
                      Text(FormatUtils.secondsToMinutesString(_playhead),
                          style: TextStyle(color: p.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle('Step count'),
            _ProgressRow(label: "Today's steps", value: '$stepCount step', percent: sTarget),
            const SizedBox(height: 20),
            _SectionTitle('Calorie'),
            _ProgressRow(label: 'Calorie expenditure', value: '$calorie kcal', percent: target),
            const SizedBox(height: 20),
            _SectionTitle('Footprint'),
            _LRRow(left: footprintResult.footprintLeft, right: footprintResult.footprintRight),
            const SizedBox(height: 20),
            _SectionTitle('Arch'),
            _LRRow(left: footprintResult.archLeft, right: footprintResult.archRight),
            const SizedBox(height: 20),
            _SectionTitle('Cadence & pace'),
            Row(
              children: [
                Expanded(child: _StatBox(label: 'Distance', value: '${record.distanceKm.toStringAsFixed(2)} km')),
                Expanded(child: _StatBox(label: 'Time', value: '${record.totalTime} min')),
                Expanded(child: _StatBox(label: 'Pace', value: '${record.pace} /km')),
              ],
            ),
            Row(
              children: [
                Expanded(child: _StatBox(label: 'Ground contact', value: '${flightContact.totalGround} ms')),
                Expanded(child: _StatBox(label: 'Cadence', value: '$cadence spm')),
                Expanded(child: _StatBox(label: 'Flight time', value: '${flightContact.totalAir} ms')),
              ],
            ),
            Row(
              children: [
                Expanded(child: _StatBox(label: 'Forefoot', value: '${leftProportion.forefootPct}%')),
                Expanded(child: _StatBox(label: 'Heel', value: '${leftProportion.hindfootPct}%')),
                Expanded(child: _StatBox(label: 'Full', value: '${leftProportion.wholePct}%')),
              ],
            ),
            const SizedBox(height: 20),
            _SectionTitle('Grounding method'),
            _LRRow(left: footprintResult.landingLeft, right: footprintResult.landingRight),
            if (record.path.isNotEmpty) ...[
              const SizedBox(height: 20),
              SizedBox(
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(record.path.first.latitude, record.path.first.longitude),
                      zoom: 16,
                    ),
                    polylines: {
                      Polyline(
                        polylineId: const PolylineId('path'),
                        color: AppColors.primary,
                        width: 4,
                        points: record.path.map((pt) => LatLng(pt.latitude, pt.longitude)).toList(),
                      ),
                    },
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Text('Left foot data changes', style: TextStyle(fontWeight: FontWeight.w700)),
            FootLineChart(data: record.line, windowSize: null, height: 200),
            const SizedBox(height: 20),
            const Text('Right foot data changes', style: TextStyle(fontWeight: FontWeight.w700)),
            FootLineChart(data: record.rightLine, windowSize: null, height: 200),
            const SizedBox(height: 20),
            _SectionTitle('Averages'),
            _AverageTable(
              lFront: lFront, rFront: rFront,
              lMid: lMid, rMid: rMid,
              lRear: lRear, rRear: rRear,
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  final String label;
  final String value;
  final int percent;

  const _ProgressRow({required this.label, required this.value, required this.percent});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
            Text(value),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: (percent / 100).clamp(0, 1).toDouble(),
            minHeight: 8,
            backgroundColor: p.surface2,
            color: AppColors.primary,
          ),
        ),
      ],
    );
  }
}

class _LRRow extends StatelessWidget {
  final String left;
  final String right;
  const _LRRow({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Left foot: $left', style: TextStyle(color: p.textSecondary)),
        Text('Right foot: $right', style: TextStyle(color: p.textSecondary)),
      ],
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: p.textSecondary, fontSize: 12)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _AverageTable extends StatelessWidget {
  final int lFront, rFront, lMid, rMid, lRear, rRear;

  const _AverageTable({
    required this.lFront,
    required this.rFront,
    required this.lMid,
    required this.rMid,
    required this.lRear,
    required this.rRear,
  });

  @override
  Widget build(BuildContext context) {
    TableRow row(String label, int l, int r) => TableRow(children: [
          Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(label)),
          Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('$l', textAlign: TextAlign.center)),
          Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text('$r', textAlign: TextAlign.center)),
        ]);

    return Table(
      border: TableBorder.all(color: context.palette.border),
      columnWidths: const {0: FlexColumnWidth(2), 1: FlexColumnWidth(1), 2: FlexColumnWidth(1)},
      children: [
        const TableRow(children: [
          Padding(padding: EdgeInsets.all(10), child: Text('')),
          Padding(padding: EdgeInsets.all(10), child: Text('Left', textAlign: TextAlign.center)),
          Padding(padding: EdgeInsets.all(10), child: Text('Right', textAlign: TextAlign.center)),
        ]),
        row('Forefoot (avg)', lFront, rFront),
        row('Midfoot (avg)', lMid, rMid),
        row('Rearfoot (avg)', lRear, rRear),
      ],
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
