import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/foot_line_data.dart';
import '../models/foot_point_layout.dart';
import '../models/insole_record.dart';
import '../models/pressure_frame.dart';
import '../models/record_summary.dart';
import '../models/user_profile.dart';
import '../services/clinical_gait_analysis.dart';
import '../services/clinical_report_service.dart';
import '../services/format_utils.dart';
import '../services/gait_screening_model.dart';
import '../services/health_calc.dart';
import '../services/personal_baseline_model.dart';
import '../services/recovery_analysis.dart';
import '../services/session_file_store.dart';
import '../state/auth_provider.dart';
import '../state/insole_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/foot_line_chart.dart';
import '../widgets/foot_pressure_view.dart';
import '../widgets/gps_path_map.dart';

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

  /// Raw per-frame data, loaded once from this session's local file --
  /// null until that load completes. Only the playback scrubber and the
  /// two full waveform charts need this; every other stat on this screen
  /// reads `record.summary`, which was computed once at save time and
  /// needs no frame data at all.
  List<PressureFrame>? _frames;
  final _fileStore = SessionFileStore();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_record == null) {
      _record = context.read<InsoleProvider>().byId(widget.recordId);
      _loadFrames();
    }
  }

  Future<void> _loadFrames() async {
    final path = _record?.framesFilePath;
    if (path == null) return;
    final frames = await _fileStore.readFramesAtPath(path);
    if (!mounted) return;
    setState(() => _frames = frames);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _play() {
    final record = _record;
    final frames = _frames;
    if (record == null || frames == null || frames.isEmpty) return;

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
      final grid = _gridAtSecond(frames, _playhead);
      setState(() {
        if (grid != null) _grid = grid;
        _playhead++;
      });
    });
  }

  /// The most recent captured frame at or before [second], since frames
  /// arrive at an uneven real-time rate (not one-per-second) -- `frames`
  /// is sorted ascending by `time` (ms since session start).
  List<List<int>>? _gridAtSecond(List<PressureFrame> frames, int second) {
    final ms = second * 1000;
    List<List<int>>? result;
    for (final f in frames) {
      if (f.time > ms) break;
      result = f.item;
    }
    return result;
  }

  void _stop() {
    _timer?.cancel();
    setState(() => _playing = false);
  }

  /// Renders a nullable metric (null when there isn't enough gait-cycle
  /// data to compute it, e.g. fewer than two heel-strikes) as '--'.
  static String _fmt(double? value, {required String suffix}) {
    if (value == null) return '--';
    return '${value.toStringAsFixed(value.abs() < 10 ? 1 : 0)}$suffix';
  }

  Future<void> _showExportSheet(
    InsoleRecord record,
    RecordSummary summary,
    UserProfile profile,
    String? email,
    RecoveryComparison recovery,
  ) async {
    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('Export as PDF'),
              subtitle: const Text('For printing or sharing with a clinician'),
              onTap: () {
                Navigator.pop(sheetContext);
                _exportPdf(record, summary, profile, email, recovery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.table_chart_outlined),
              title: const Text('Export as CSV'),
              subtitle: const Text('For spreadsheets or EHR import'),
              onTap: () {
                Navigator.pop(sheetContext);
                _exportCsv(record, summary, profile, email, recovery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPdf(
    InsoleRecord record,
    RecordSummary summary,
    UserProfile profile,
    String? email,
    RecoveryComparison recovery,
  ) async {
    final bytes = await ClinicalReportService.buildPdf(
      record: record,
      gait: summary.clinical,
      profile: profile,
      patientEmail: email,
      recovery: recovery,
    );
    await Printing.sharePdf(bytes: bytes, filename: '${record.name}_gait_report.pdf');
  }

  Future<void> _exportCsv(
    InsoleRecord record,
    RecordSummary summary,
    UserProfile profile,
    String? email,
    RecoveryComparison recovery,
  ) async {
    final csv = ClinicalReportService.buildCsv(
      record: record,
      gait: summary.clinical,
      recovery: recovery,
      profile: profile,
      patientEmail: email,
    );
    final bytes = Uint8List.fromList(utf8.encode(csv));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile.fromData(bytes, name: '${record.name}_gait_report.csv', mimeType: 'text/csv')],
      ),
    );
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
    final insole = context.watch<InsoleProvider>();
    final summary = record.summary;
    final gait = summary.clinical;
    final frames = _frames;

    final recovery = RecoveryAnalysis.compare(
      records: insole.list,
      milestoneDate: DateTime.tryParse(auth.profile.recoveryMilestoneDate ?? ''),
      condition: RecoveryCondition.values.firstWhere(
        (c) => c.name == auth.profile.recoveryConditionType,
        orElse: () => RecoveryCondition.other,
      ),
    );

    final speedMps = record.totalTime > 0 ? record.distanceKm * 1000 / (record.totalTime * 60) : null;
    final screening = GaitScreeningModel.predict(gait: gait, speedMps: speedMps);
    final personalBaseline = PersonalBaselineModel.evaluate(history: insole.list, current: record);
    final strideLengthM = ClinicalGaitAnalysis.strideLengthMeters(
      distanceKm: record.distanceKm,
      leftStepCount: gait.left.stepCount,
      rightStepCount: gait.right.stepCount,
    );

    final calorie = HealthCalc.calculateCalories(record.distanceKm, auth.profile.weightKg);
    final target = (calorie / 5000 * 100).round();
    final sTarget = (summary.stepCount / 10000 * 100).round();

    FootLineData? leftLine;
    FootLineData? rightLine;
    if (frames != null) {
      leftLine = FootLineData.fromFrames(frames, FootPointLayout.left);
      rightLine = FootLineData.fromFrames(frames, FootPointLayout.right);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(record.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export clinical report',
            onPressed: () => _showExportSheet(record, summary, auth.profile, auth.email, recovery),
          ),
        ],
      ),
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
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        if (_heatMode) ...[const HeatLegend(), const SizedBox(width: 12)],
                        FootPressureView(grid: _grid, isRight: false, heatMode: _heatMode),
                        const SizedBox(width: 12),
                        FootPressureView(grid: _grid, isRight: true, heatMode: _heatMode),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      IconButton(
                        icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                            color: AppColors.primary, size: 36),
                        onPressed:
                            (frames == null || frames.isEmpty) ? null : (_playing ? _stop : _play),
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
            _ProgressRow(label: "Today's steps", value: '${summary.stepCount} step', percent: sTarget),
            const SizedBox(height: 20),
            _SectionTitle('Calorie'),
            _ProgressRow(label: 'Calorie expenditure', value: '$calorie kcal', percent: target),
            const SizedBox(height: 20),
            _SectionTitle('Footprint'),
            _LRRow(left: summary.footprintLeft, right: summary.footprintRight),
            const SizedBox(height: 20),
            _SectionTitle('Arch'),
            _LRRow(left: summary.archLeft, right: summary.archRight),
            const SizedBox(height: 20),
            _SectionTitle('Cadence & pace'),
            Row(
              children: [
                Expanded(child: _StatBox(label: 'Distance', value: '${record.distanceKm.toStringAsFixed(2)} km')),
                Expanded(child: _StatBox(label: 'Time', value: '${record.totalTime} min')),
                Expanded(child: _StatBox(label: 'Pace', value: '${record.pace} /km')),
                Expanded(
                  child: _StatBox(
                    label: 'Stride length',
                    value: strideLengthM != null ? '${strideLengthM.toStringAsFixed(2)} m' : '--',
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(child: _StatBox(label: 'Ground contact', value: '${summary.groundContactMs} ms')),
                Expanded(child: _StatBox(label: 'Cadence', value: '${summary.cadenceSpm} spm')),
                Expanded(child: _StatBox(label: 'Flight time', value: '${summary.flightMs} ms')),
              ],
            ),
            Row(
              children: [
                Expanded(child: _StatBox(label: 'Forefoot', value: '${summary.forefootPct}%')),
                Expanded(child: _StatBox(label: 'Heel', value: '${summary.hindfootPct}%')),
                Expanded(child: _StatBox(label: 'Full', value: '${summary.wholePct}%')),
              ],
            ),
            if (summary.fogEventCount > 0) ...[
              const SizedBox(height: 20),
              _SectionTitle('Freezing-of-gait signal'),
              Row(
                children: [
                  Expanded(child: _StatBox(label: 'Episodes', value: '${summary.fogEventCount}')),
                  Expanded(
                      child: _StatBox(
                          label: 'Total freeze time',
                          value: '${(summary.totalFreezeMs / 1000).toStringAsFixed(1)} s')),
                ],
              ),
            ],
            const SizedBox(height: 20),
            _SectionTitle('Grounding method'),
            _LRRow(left: summary.landingLeft, right: summary.landingRight),
            const SizedBox(height: 20),
            _SectionTitle('Clinical gait metrics'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: p.card(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _StatBox(
                          label: 'Cadence',
                          value: _fmt(gait.cadenceStepsPerMin, suffix: ' spm'),
                        ),
                      ),
                      Expanded(
                        child: _StatBox(
                          label: 'Double support',
                          value: _fmt(gait.doubleSupportPercent, suffix: '%'),
                        ),
                      ),
                      Expanded(
                        child: _StatBox(
                          label: 'Single support',
                          value: _fmt(gait.singleSupportPercent, suffix: '%'),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  const _ClinicalMetricHeader(),
                  _ClinicalMetricRow(
                    label: 'Stride time',
                    left: _fmt(gait.left.strideTimeMeanMs, suffix: ' ms'),
                    right: _fmt(gait.right.strideTimeMeanMs, suffix: ' ms'),
                  ),
                  _ClinicalMetricRow(
                    label: 'Stride time CV',
                    left: _fmt(gait.left.strideTimeCvPercent, suffix: '%'),
                    right: _fmt(gait.right.strideTimeCvPercent, suffix: '%'),
                  ),
                  _ClinicalMetricRow(
                    label: 'Stance time',
                    left: _fmt(gait.left.stanceTimeMeanMs, suffix: ' ms'),
                    right: _fmt(gait.right.stanceTimeMeanMs, suffix: ' ms'),
                  ),
                  _ClinicalMetricRow(
                    label: 'Swing time',
                    left: _fmt(gait.left.swingTimeMeanMs, suffix: ' ms'),
                    right: _fmt(gait.right.swingTimeMeanMs, suffix: ' ms'),
                  ),
                  _ClinicalMetricRow(
                    label: 'Swing time CV',
                    left: _fmt(gait.left.swingTimeCvPercent, suffix: '%'),
                    right: _fmt(gait.right.swingTimeCvPercent, suffix: '%'),
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: _StatBox(
                          label: 'Stride asymmetry',
                          value: _fmt(gait.strideTimeAsymmetryPercent, suffix: '%'),
                        ),
                      ),
                      Expanded(
                        child: _StatBox(
                          label: 'Stance asymmetry',
                          value: _fmt(gait.stanceTimeAsymmetryPercent, suffix: '%'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Raw gait measurements from heel-strike/toe-off detection. '
                    'Not a diagnosis -- for review by a clinician.',
                    style: TextStyle(color: p.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (screening != null) ...[
              const SizedBox(height: 20),
              _GaitScreeningCard(result: screening),
            ],
            const SizedBox(height: 20),
            _PersonalBaselineCard(result: personalBaseline),
            if (record.path.isNotEmpty) ...[
              const SizedBox(height: 20),
              GpsPathMap(path: record.path),
            ],
            const SizedBox(height: 20),
            const Text('Left foot data changes', style: TextStyle(fontWeight: FontWeight.w700)),
            if (leftLine == null)
              const SizedBox(height: 200)
            else
              FootLineChart(data: leftLine, windowSize: null, height: 200),
            const SizedBox(height: 20),
            const Text('Right foot data changes', style: TextStyle(fontWeight: FontWeight.w700)),
            if (rightLine == null)
              const SizedBox(height: 200)
            else
              FootLineChart(data: rightLine, windowSize: null, height: 200),
            const SizedBox(height: 20),
            _SectionTitle('Averages'),
            _AverageTable(
              lFront: summary.lFront, rFront: summary.rFront,
              lMid: summary.lMid, rMid: summary.rMid,
              lRear: summary.lRear, rRear: summary.rRear,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows [GaitScreeningModel]'s output as a qualitative band only, never a
/// raw percentage -- see that class's doc comment for why a precise number
/// would overstate how confident this model actually is. Deliberately
/// paired with an always-visible disclaimer, not a one-time tooltip.
class _GaitScreeningCard extends StatelessWidget {
  final GaitScreeningResult result;
  const _GaitScreeningCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (label, color) = switch (result.band) {
      GaitScreeningBand.low => ('Low signal', AppColors.success),
      GaitScreeningBand.inconclusive => ('Inconclusive', AppColors.warning),
      GaitScreeningBand.elevated => ('Elevated signal', AppColors.warning),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: p.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Gait pattern screening', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'An experimental signal comparing this session\'s gait pattern to a research '
            'dataset of Parkinson\'s patients and healthy adults. This is NOT a diagnosis, '
            'has not been validated on this app\'s own hardware, and should never replace '
            'a clinician\'s assessment -- treat it only as a prompt to discuss with one.',
            style: TextStyle(color: p.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

/// Shows [PersonalBaselineModel]'s output: how this session compares to
/// THIS patient's own history, not any external population. Deliberately
/// distinct in tone from [_GaitScreeningCard] above it -- that one carries
/// an external-validity disclaimer because it's scored against someone
/// else's dataset; this one needs no such disclaimer because every number
/// it's compared to came from this same patient's own past sessions.
class _PersonalBaselineCard extends StatelessWidget {
  final PersonalBaselineResult result;
  const _PersonalBaselineCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (label, color) = switch (result.level) {
      PersonalAnomalyLevel.normal => ('Within your normal range', AppColors.success),
      PersonalAnomalyLevel.mild => ('Mild deviation', AppColors.warning),
      PersonalAnomalyLevel.significant => ('Significant deviation', AppColors.warning),
      PersonalAnomalyLevel.insufficientData => ('Still learning', p.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: p.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Your personal baseline', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(result.summary, style: TextStyle(color: p.textSecondary, fontSize: 12)),
          if (result.deviations.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...result.deviations.map(
              (d) => Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  '${d.displayLabel}: ${d.value.toStringAsFixed(1)} (your average: '
                  '${d.baselineMean.toStringAsFixed(1)}, ${d.zScore.abs().toStringAsFixed(1)} SD '
                  '${d.zScore >= 0 ? 'above' : 'below'})',
                  style: TextStyle(color: p.textTertiary, fontSize: 11),
                ),
              ),
            ),
          ],
        ],
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

class _ClinicalMetricHeader extends StatelessWidget {
  const _ClinicalMetricHeader();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = TextStyle(color: p.textSecondary, fontSize: 12, fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Expanded(flex: 3, child: SizedBox()),
          Expanded(flex: 2, child: Text('Left', textAlign: TextAlign.center, style: style)),
          Expanded(flex: 2, child: Text('Right', textAlign: TextAlign.center, style: style)),
        ],
      ),
    );
  }
}

class _ClinicalMetricRow extends StatelessWidget {
  final String label;
  final String left;
  final String right;
  const _ClinicalMetricRow({required this.label, required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(label, style: TextStyle(color: p.textSecondary))),
          Expanded(flex: 2, child: Text(left, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
          Expanded(flex: 2, child: Text(right, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
        ],
      ),
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
