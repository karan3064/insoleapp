import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/foot_line_data.dart';
import '../models/foot_point_layout.dart';
import '../models/insole_record.dart';
import '../models/mood_entry.dart';
import '../services/health_calc.dart';
import '../services/home_ai_service.dart';
import '../services/mood_gait_correlation.dart';
import '../services/mood_service.dart';
import '../services/session_file_store.dart';
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
    int balancePercent = 0;
    int cadence = 0;
    int groundContactMs = 0;
    String footprintLabel = '';
    String archLabel = '';

    if (latest != null) {
      final summary = latest.summary;
      sCount = summary.stepCount;
      calorie = HealthCalc.calculateCalories(latest.distanceKm, profile.weightKg);
      balancePercent = summary.balancePercent;
      cadence = summary.cadenceSpm;
      groundContactMs = summary.groundContactMs;
      footprintLabel = summary.footprintLeft;
      archLabel = summary.archLeft;
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
            const SizedBox(height: 16),
            _AiGreetingCard(records: insole.list, displayName: profile.displayName),
            const SizedBox(height: 12),
            if (auth.uid != null) _MoodCheckInCard(uid: auth.uid!, records: insole.list),
            const SizedBox(height: 16),
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

class _RecentDataCard extends StatefulWidget {
  final InsoleRecord record;

  const _RecentDataCard({required this.record});

  @override
  State<_RecentDataCard> createState() => _RecentDataCardState();
}

class _RecentDataCardState extends State<_RecentDataCard> {
  static final _fileStore = SessionFileStore();
  FootLineData? _line;

  @override
  void initState() {
    super.initState();
    _loadLine();
  }

  @override
  void didUpdateWidget(_RecentDataCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.id != widget.record.id) {
      _line = null;
      _loadLine();
    }
  }

  Future<void> _loadLine() async {
    // The full waveform is loaded from this session's local frame file --
    // never eagerly held on `InsoleRecord` itself, so the dashboard stays
    // cheap regardless of how long the session ran.
    final path = widget.record.framesFilePath;
    if (path == null) return;
    final frames = await _fileStore.readFramesAtPath(path);
    if (!mounted) return;
    setState(() => _line = FootLineData.fromFrames(frames, FootPointLayout.left));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final line = _line;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => DetailScreen(recordId: widget.record.id)),
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
            Text('Steps: ${widget.record.summary.stepCount}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (line == null)
              const SizedBox(height: 100)
            else
              FootLineChart(data: line, windowSize: null, height: 100),
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

/// The very first AI touchpoint a user sees -- a personalized one-line
/// greeting (Gemini via `HomeAiService.generateHomeInsight`) built from
/// whatever recent trend context is on hand, never raw sensor data. Falls
/// back to a generic time-of-day greeting on any failure, so a flaky
/// network call never blocks the home screen from rendering.
class _AiGreetingCard extends StatefulWidget {
  final List<InsoleRecord> records;
  final String? displayName;
  const _AiGreetingCard({required this.records, required this.displayName});

  @override
  State<_AiGreetingCard> createState() => _AiGreetingCardState();
}

class _AiGreetingCardState extends State<_AiGreetingCard> {
  String? _greeting;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  static String _timeOfDay() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'morning';
    if (hour < 17) return 'afternoon';
    return 'evening';
  }

  Future<void> _load() async {
    final recent = widget.records.take(7).toList();
    final greetingContext = {
      'timeOfDay': _timeOfDay(),
      if (widget.displayName != null) 'displayName': widget.displayName,
      'recentSessionCount': recent.length,
      if (recent.isNotEmpty) 'latestCadenceSpm': recent.first.summary.cadenceSpm,
      if (recent.isNotEmpty) 'latestStepCount': recent.first.summary.stepCount,
    };
    final greeting = await HomeAiService.generateHomeInsight(greetingContext);
    if (!mounted) return;
    setState(() {
      _greeting = greeting;
      _loading = false;
    });
  }

  String _fallbackGreeting() {
    final name = widget.displayName;
    return 'Good ${_timeOfDay()}${name != null ? ', $name' : ''} -- ready for today\'s walk?';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_loading) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: AppColors.primary, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(_greeting ?? _fallbackGreeting(), style: TextStyle(color: p.text, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

/// "How are you feeling today?" -- a quick daily mood check-in with a
/// short AI (Gemini) empathetic reply, plus (once there's enough history)
/// `MoodGaitCorrelation`'s insight into whether mood and measured gait
/// quality move together for this patient. One check-in per calendar day.
class _MoodCheckInCard extends StatefulWidget {
  final String uid;
  final List<InsoleRecord> records;
  const _MoodCheckInCard({required this.uid, required this.records});

  @override
  State<_MoodCheckInCard> createState() => _MoodCheckInCardState();
}

class _MoodCheckInCardState extends State<_MoodCheckInCard> {
  final _service = MoodService();
  MoodEntry? _todayEntry;
  MoodGaitCorrelationResult? _correlation;
  bool _loading = true;
  bool _submitting = false;
  String? _aiReply;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      _service.todayEntry(widget.uid),
      _service.recentEntries(widget.uid),
    ]);
    if (!mounted) return;
    final entry = results[0] as MoodEntry?;
    final history = results[1] as List<MoodEntry>;
    setState(() {
      _todayEntry = entry;
      _correlation = MoodGaitCorrelation.evaluate(moodEntries: history, records: widget.records);
      _loading = false;
    });
  }

  Future<void> _submit(int score) async {
    setState(() => _submitting = true);
    await _service.checkIn(widget.uid, score: score);
    final reply = await HomeAiService.respondToMoodCheckIn(score: score);
    if (!mounted) return;
    setState(() {
      _todayEntry = MoodEntry(id: MoodEntry.dateKey(DateTime.now()), date: DateTime.now(), score: score);
      _aiReply = reply;
      _submitting = false;
    });
  }

  static const _moodEmoji = ['😞', '🙁', '😐', '🙂', '😄'];
  static const _moodLabels = ['Very low', 'Low', 'Okay', 'Good', 'Great'];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_loading) return const SizedBox.shrink();

    final entry = _todayEntry;
    final correlation = _correlation;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: p.card(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('How are you feeling today?', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          if (entry == null) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(5, (i) {
                final score = i + 1;
                return InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: _submitting ? null : () => _submit(score),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: p.surface2, shape: BoxShape.circle),
                    child: Text(_moodEmoji[i], style: const TextStyle(fontSize: 20)),
                  ),
                );
              }),
            ),
            if (_submitting) ...[
              const SizedBox(height: 10),
              const Center(
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ],
          ] else ...[
            Text('Checked in today: ${_moodLabels[entry.score - 1]}',
                style: TextStyle(color: p.textSecondary)),
            if (_aiReply != null) ...[
              const SizedBox(height: 8),
              Text(_aiReply!, style: TextStyle(color: p.text, fontSize: 13)),
            ],
          ],
          if (correlation != null && correlation.correlations.isNotEmpty) ...[
            const Divider(height: 24),
            Row(
              children: [
                Icon(Icons.insights, size: 16, color: p.textSecondary),
                const SizedBox(width: 6),
                Text('Mood & gait pattern', style: TextStyle(color: p.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 4),
            Text(correlation.summary, style: TextStyle(color: p.textSecondary, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
