import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/insole_device.dart';
import '../state/ble_provider.dart';
import '../theme/app_colors.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BleProvider>().startScan();
    });
  }

  @override
  void dispose() {
    context.read<BleProvider>().stopScan();
    super.dispose();
  }

  Future<void> _connect(InsoleDevice device) async {
    final ble = context.read<BleProvider>();
    final ok = await ble.connect(device);

    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to connect')),
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
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ble.discovered.isEmpty
                  ? const Center(
                      child: Text('Scanning for insoles...',
                          style: TextStyle(color: AppColors.textSecondary)),
                    )
                  : ListView.separated(
                      itemCount: ble.discovered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final d = ble.discovered[i];
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: const BoxDecoration(
                                  color: AppColors.btnColor,
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
                                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
