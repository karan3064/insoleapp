import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      FootPressureView(grid: ble.grid, isRight: false, heatMode: _heatMode),
                      FootPressureView(grid: ble.grid, isRight: true, heatMode: _heatMode),
                    ],
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
