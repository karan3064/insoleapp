import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../services/format_utils.dart';
import '../state/auth_provider.dart';
import '../state/ble_provider.dart';
import '../state/insole_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/foot_line_chart.dart';
import '../widgets/foot_pressure_view.dart';
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

  Future<void> _startTest() async {
    await context.read<BleProvider>().startTest();
    setState(() {});
  }

  Future<void> _endTest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('End test?'),
        content: const Text('This will stop data collection and save the session.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('End')),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final ble = context.read<BleProvider>();
    final insole = context.read<InsoleProvider>();
    final auth = context.read<AuthProvider>();

    final deviceName = ble.connectedDevices.isNotEmpty ? ble.connectedDevices.first.name : 'Insole';
    final record = ble.stopTest(insole.nextId, deviceName);

    await insole.saveRecord(record);
    unawaited(insole.syncRecord(auth.uid, record));

    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => DetailScreen(recordId: record.id)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Test')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(20),
              ),
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
                  Text(
                    FormatUtils.secondsToMinutesString(ble.testSeconds),
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: ble.isTesting ? null : _startTest,
                    child: const Text('Start test'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton(
                    onPressed: ble.isTesting ? _endTest : null,
                    child: const Text('End test'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (ble.path.isNotEmpty)
              SizedBox(
                height: 220,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: LatLng(ble.path.first.latitude, ble.path.first.longitude),
                      zoom: 16,
                    ),
                    polylines: {
                      Polyline(
                        polylineId: const PolylineId('path'),
                        color: AppColors.primary,
                        width: 4,
                        points: ble.path.map((p) => LatLng(p.latitude, p.longitude)).toList(),
                      ),
                    },
                    myLocationButtonEnabled: false,
                    zoomControlsEnabled: false,
                  ),
                ),
              ),
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
                color: active ? AppColors.bg : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.border),
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
