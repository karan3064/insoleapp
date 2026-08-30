import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/insole_record.dart';
import '../services/gait_analysis.dart';
import '../services/health_calc.dart';
import '../state/auth_provider.dart';
import '../state/ble_provider.dart';
import '../state/insole_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/activity_rings.dart';
import '../widgets/foot_line_chart.dart';
import '../widgets/metric_card.dart';
import 'bluetooth_screen.dart';
import 'detail_screen.dart';
import 'gather_screen.dart';

/// Mirrors `pages/index/index.vue`: today's activity rings, quick stats,
/// quick actions, and a recent-data preview.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final insole = context.watch<InsoleProvider>();
    final latest = insole.list.isNotEmpty ? insole.list.first : null;

    final profile = auth.profile;
    final bmi = HealthCalc.calculateBMI(profile.weightKg, profile.heightCm);
    final bmiCategory = HealthCalc.bmiCategory(bmi);

    int sCount = 0;
    int calorie = 0;
    double lFoot = 0;
    double rFoot = 0;
    int balancePercent = 0;
    int cadence = 0;
    int groundContactMs = 0;
    String footprintLabel = '';
    String archLabel = '';

    if (latest != null) {
      sCount = GaitAnalysis.processFrames(latest.details);
      calorie = HealthCalc.calculateCalories(latest.distanceKm, profile.weightKg);

      const allKeys = [
        'data', 'data2', 'data3', 'data4', 'data5', 'data6', 'data7', 'data8',
        'data9', 'data10', 'data11', 'data12', 'data13', 'data14', 'data15', 'data16',
      ];
      lFoot = GaitAnalysis.calculateAverage(latest.line, allKeys);
      rFoot = GaitAnalysis.calculateAverage(latest.rightLine, allKeys);
      balancePercent = GaitAnalysis.calculateBalance(lFoot, rFoot);
      cadence = GaitAnalysis.calculateCadence(sCount, latest.time);

      final truncated = GaitAnalysis.truncateToSevenCols(latest.details);
      groundContactMs = GaitAnalysis.analyzeFlightAndContact(truncated).totalGround;

      final fp = GaitAnalysis.footprint(latest.line, latest.rightLine);
      footprintLabel = fp.footprintLeft;
      archLabel = fp.archLeft;
    }

    final stepGoal = 6000;
    final calorieGoal = 500;
    final stepsPercent = sCount == 0 ? 0.0 : (sCount / stepGoal * 100).clamp(0, 100).toDouble();
    final caloriePercent = calorie == 0 ? 0.0 : (calorie / calorieGoal * 100).clamp(0, 100).toDouble();
    final p = context.palette;

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  profile.displayName != null ? 'Hello, ${profile.displayName}' : 'Hello there',
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
                ),
                CircleAvatar(
                  radius: 22,
                  backgroundColor: p.surface,
                  child: Icon(Icons.person, color: p.textSecondary),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: p.card(),
              child: Column(
                children: [
                  ActivityRings(
                    size: 200,
                    rings: [
                      RingSpec(percent: stepsPercent, color: AppColors.primary, trackColor: p.surface2),
                      RingSpec(percent: caloriePercent, color: AppColors.warning, trackColor: p.surface2),
                      RingSpec(
                          percent: balancePercent.toDouble(),
                          color: const Color(0xFF60A5FA),
                          trackColor: p.surface2),
                    ],
                    center: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$sCount',
                            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700)),
                        Text('steps today', style: TextStyle(color: p.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _Stat(color: AppColors.primary, value: '$calorie', label: 'calorie kcal'),
                      _Stat(color: AppColors.warning, value: '$balancePercent', label: 'balance %'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: MetricCard(
                    title: 'BMI',
                    value: bmi?.toString() ?? '--',
                    subtitle: bmiCategory ?? 'Set your profile',
                    gradient: AppColors.gradBody,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    title: 'Cadence',
                    value: '$cadence',
                    subtitle: 'spm',
                    gradient: AppColors.gradActivity,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: MetricCard(
                    title: 'Ground contact',
                    value: '$groundContactMs',
                    subtitle: 'ms',
                    gradient: AppColors.gradMechanics,
                  ),
                ),
              ],
            ),
            if (latest != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: MetricCard(
                      title: 'Footprint',
                      value: footprintLabel,
                      gradient: AppColors.gradMechanics,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: MetricCard(
                      title: 'Arch',
                      value: archLabel,
                      gradient: AppColors.gradMechanics,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 28),
            const Text('Quick actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            _ActionCard(
              icon: Icons.bluetooth,
              label: context.watch<BleProvider>().connectedDevices.length >= 2
                  ? 'Resume live test'
                  : 'Connect insoles',
              gradient: AppColors.gradActivity,
              onTap: () {
                // Already connected -- skip straight back to the live test
                // instead of the scan screen (already-connected peripherals
                // stop advertising, so re-scanning would just find nothing
                // and look like you need to reconnect).
                final alreadyConnected = context.read<BleProvider>().connectedDevices.length >= 2;
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => alreadyConnected ? const GatherScreen() : const BluetoothScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 28),
            const Text('Data overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (latest != null)
              _RecentDataCard(record: latest)
            else
              const _EmptyState(),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final Color color;
  final String value;
  final String label;

  const _Stat({required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(color: context.palette.textSecondary, fontSize: 11)),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Gradient gradient;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: p.card(),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(gradient: gradient, shape: BoxShape.circle),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 16),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _RecentDataCard extends StatelessWidget {
  final InsoleRecord record;

  const _RecentDataCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final stepCount = GaitAnalysis.processFrames(record.details);
    final p = context.palette;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DetailScreen(recordId: record.id)),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: p.card(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Recent insole data', style: TextStyle(color: p.textSecondary)),
                Icon(Icons.chevron_right, color: p.textSecondary),
              ],
            ),
            const SizedBox(height: 8),
            Text('Steps: $stepCount', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            FootLineChart(data: record.line, windowSize: null, height: 100),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      decoration: p.card(),
      child: Text('No test data yet', style: TextStyle(color: p.textSecondary)),
    );
  }
}
