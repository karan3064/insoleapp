import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/insole_device.dart';
import '../state/ble_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import 'gather_screen.dart';

/// Mirrors `pages/bluetooth/bluetooth.vue`: scans for `B2U*` insole
/// peripherals and lets the user connect/disconnect. Once 2 devices are
/// connected (left + right insole) it moves on to the live test screen.
class BluetoothScreen extends StatefulWidget {
  const BluetoothScreen({super.key});

  @override
  State<BluetoothScreen> createState() => _BluetoothScreenState();
}

class _BluetoothScreenState extends State<BluetoothScreen> {
  bool _navigated = false;
  late final BleProvider _ble;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ble = context.read<BleProvider>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleProvider>().startScan();
    });
  }

  @override
  void dispose() {
    // Captured in didChangeDependencies -- looking up an inherited widget
    // via context.read() here is unsafe once the element is deactivating.
    _ble.stopScan();
    super.dispose();
  }

  Future<void> _connect(InsoleDevice device) async {
    final ble = context.read<BleProvider>();
    final ok = await ble.connect(device);

    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ble.lastError ?? 'Failed to connect')),
      );
      return;
    }

    if (ble.connectedDevices.length >= 2 && !_navigated) {
      _navigated = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const GatherScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = context.watch<BleProvider>();
    final p = context.palette;

    return Scaffold(
      appBar: AppBar(title: const Text('Devices')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Available devices',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                if (ble.isScanning)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                  )
                else
                  TextButton(onPressed: ble.startScan, child: const Text('Rescan')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Connect both the left and right insole (${ble.connectedDevices.length}/2 connected)',
              style: TextStyle(color: p.textSecondary, fontSize: 13),
            ),
            if (ble.lastError != null) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.12),
                  border: Border.all(color: AppColors.error),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(ble.lastError!, style: const TextStyle(color: AppColors.error)),
              ),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: ble.discovered.isEmpty
                  ? Center(
                      child: Text(
                        ble.isScanning ? 'Scanning for insoles...' : 'No devices found',
                        style: TextStyle(color: p.textSecondary),
                      ),
                    )
                  : ListView.separated(
                      itemCount: ble.discovered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final d = ble.discovered[i];
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: p.card(radius: 16),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: p.btnColor,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.bluetooth, color: AppColors.primary),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(d.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                    Text(
                                      d.connected ? 'Connected' : 'Not connected',
                                      style: TextStyle(color: p.textSecondary, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              if (d.connecting)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              else
                                OutlinedButton(
                                  onPressed: () => d.connected
                                      ? context.read<BleProvider>().disconnect(d)
                                      : _connect(d),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor:
                                        d.connected ? AppColors.error : AppColors.primary,
                                    side: BorderSide(
                                      color: d.connected ? AppColors.error : AppColors.primary,
                                    ),
                                  ),
                                  child: Text(d.connected ? 'Disconnect' : 'Connect'),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
