import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/health_calc.dart';
import '../state/auth_provider.dart';
import '../theme/app_colors.dart';
import '../widgets/page_header.dart';

/// Mirrors `pages/my/my.vue`: profile fields used by the health
/// calculations (height/weight/sex/birth date), plus logout.
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _editNumberField(
    BuildContext context, {
    required String title,
    required String suffix,
    required double? current,
    required ValueChanged<double?> onSave,
  }) async {
    final controller = TextEditingController(text: current?.toString() ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: InputDecoration(suffixText: suffix),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null) return;
    onSave(double.tryParse(result));
  }

  Future<void> _editNameField(BuildContext context, String? current, ValueChanged<String?> onSave) async {
    final controller = TextEditingController(text: current ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text('Name'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (result == null) return;
    onSave(result.isEmpty ? null : result);
  }

  Future<void> _chooseSex(BuildContext context, AuthProvider auth) async {
    final value = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: const Text('Male'), onTap: () => Navigator.pop(context, 'male')),
            ListTile(title: const Text('Female'), onTap: () => Navigator.pop(context, 'female')),
            ListTile(title: const Text('Other'), onTap: () => Navigator.pop(context, 'other')),
          ],
        ),
      ),
    );
    if (value == null) return;
    await auth.updateProfile(auth.profile.copyWith(sex: value));
  }

  Future<void> _pickBirthDate(BuildContext context, AuthProvider auth) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.tryParse(auth.profile.birthDate ?? '') ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    final iso = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    await auth.updateProfile(auth.profile.copyWith(birthDate: iso));
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;
    final bmi = HealthCalc.calculateBMI(profile.weightKg, profile.heightCm);
    final bmiCategory = HealthCalc.bmiCategory(bmi);
    const sexLabels = {'male': 'Man', 'female': 'Woman', 'other': 'Other'};

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          children: [
            const PageHeader(title: 'Me'),
            Center(
              child: Column(
                children: [
                  const CircleAvatar(
                    radius: 44,
                    backgroundColor: AppColors.surface,
                    child: Icon(Icons.person, size: 44, color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () => _editNameField(
                      context,
                      profile.displayName,
                      (v) => auth.updateProfile(profile.copyWith(displayName: v)),
                    ),
                    child: Text(
                      profile.displayName ?? auth.email ?? 'Guest',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (auth.uid != null) ...[
                    const SizedBox(height: 4),
                    Text('UID: ${auth.uid}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            _SettingsGroup(children: [
              _SettingsRow(
                label: 'Sex',
                value: sexLabels[profile.sex] ?? 'Set',
                onTap: () => _chooseSex(context, auth),
              ),
              _SettingsRow(
                label: 'Birth date',
                value: profile.birthDate ?? 'Set',
                onTap: () => _pickBirthDate(context, auth),
              ),
              _SettingsRow(
                label: 'Height',
                value: profile.heightCm != null ? '${profile.heightCm}cm' : 'Set',
                onTap: () => _editNumberField(
                  context,
                  title: 'Height',
                  suffix: 'cm',
                  current: profile.heightCm,
                  onSave: (v) => auth.updateProfile(profile.copyWith(heightCm: v)),
                ),
              ),
              _SettingsRow(
                label: 'Weight',
                value: profile.weightKg != null ? '${profile.weightKg}kg' : 'Set',
                onTap: () => _editNumberField(
                  context,
                  title: 'Weight',
                  suffix: 'kg',
                  current: profile.weightKg,
                  onSave: (v) => auth.updateProfile(profile.copyWith(weightKg: v)),
                ),
                last: true,
              ),
            ]),
            if (bmi != null) ...[
              const SizedBox(height: 16),
              _SettingsGroup(
                accent: true,
                children: [
                  _SettingsRow(label: 'BMI', value: '$bmi · $bmiCategory', last: true),
                ],
              ),
            ],
            const SizedBox(height: 32),
            if (auth.uid != null)
              OutlinedButton(
                onPressed: () async {
                  await auth.logout();
                  if (context.mounted) {
                    Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                  }
                },
                child: const Text('Log out'),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  final bool accent;

  const _SettingsGroup({required this.children, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        gradient: accent ? AppColors.gradOrange : null,
        color: accent ? null : AppColors.surface,
        border: accent ? null : Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: children),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool last;

  const _SettingsRow({required this.label, required this.value, this.onTap, this.last = false});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          border: last ? null : const Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
            Text(value, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
