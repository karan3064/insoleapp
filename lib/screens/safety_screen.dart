import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../models/family_contact.dart';
import '../models/safe_zone.dart';
import '../services/geofence_service.dart';
import '../state/auth_provider.dart';
import '../state/ble_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/page_header.dart';

/// Lets the patient (or whoever manages their account) set a home safe
/// zone and a family-contacts list, so `BleProvider` can alert those
/// contacts if a session's GPS path moves outside it -- see
/// `GeofenceTracker` for the detection logic and `functions/` for actual
/// alert delivery. Family contacts don't get their own login; they join
/// via an invite code on `JoinFamilyContactScreen`.
class SafetyScreen extends StatefulWidget {
  const SafetyScreen({super.key});

  @override
  State<SafetyScreen> createState() => _SafetyScreenState();
}

class _SafetyScreenState extends State<SafetyScreen> {
  final _service = GeofenceService();
  SafeZone? _zone;
  List<FamilyContact> _contacts = [];
  bool _loading = true;
  bool _savingZone = false;

  String? get _uid => context.read<AuthProvider>().uid;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) {
      setState(() => _loading = false);
      return;
    }
    final results = await Future.wait([_service.getSafeZone(uid), _service.listFamilyContacts(uid)]);
    if (!mounted) return;
    setState(() {
      _zone = results[0] as SafeZone?;
      _contacts = results[1] as List<FamilyContact>;
      _loading = false;
    });
  }

  Future<void> _applyZoneToTracker() async {
    final uid = _uid;
    if (!mounted || uid == null) return;
    context.read<BleProvider>().configureSafety(uid: uid, zone: _zone);
  }

  Future<void> _setZoneToCurrentLocation() async {
    final uid = _uid;
    if (uid == null) return;

    setState(() => _savingZone = true);
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final position = await Geolocator.getCurrentPosition();
      final zone = SafeZone(
        label: _zone?.label ?? 'Home',
        latitude: position.latitude,
        longitude: position.longitude,
        radiusMeters: _zone?.radiusMeters ?? 300,
      );
      await _service.setSafeZone(uid, zone);
      if (!mounted) return;
      setState(() => _zone = zone);
      await _applyZoneToTracker();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not get location: $e')));
    } finally {
      if (mounted) setState(() => _savingZone = false);
    }
  }

  Future<void> _setRadius(double radiusMeters) async {
    final uid = _uid;
    final zone = _zone;
    if (uid == null || zone == null) return;

    final updated = SafeZone(
      label: zone.label,
      latitude: zone.latitude,
      longitude: zone.longitude,
      radiusMeters: radiusMeters,
    );
    setState(() => _zone = updated);
    await _service.setSafeZone(uid, updated);
    await _applyZoneToTracker();
  }

  Future<void> _removeZone() async {
    final uid = _uid;
    if (uid == null) return;
    await _service.deleteSafeZone(uid);
    if (!mounted) return;
    setState(() => _zone = null);
    await _applyZoneToTracker();
  }

  Future<void> _addContact() async {
    final uid = _uid;
    if (uid == null) return;

    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.palette.surface,
        title: const Text('Add family contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Name')),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(labelText: 'Email'),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Add')),
        ],
      ),
    );

    if (saved != true || nameController.text.trim().isEmpty || emailController.text.trim().isEmpty) return;

    await _service.addFamilyContact(uid, name: nameController.text.trim(), email: emailController.text.trim());
    await _load();
  }

  Future<void> _removeContact(FamilyContact contact) async {
    final uid = _uid;
    if (uid == null) return;
    await _service.removeFamilyContact(uid, contact.id);
    await _load();
  }

  Future<void> _copyInviteCode(FamilyContact contact) async {
    final uid = _uid;
    if (uid == null) return;
    await Clipboard.setData(ClipboardData(text: '$uid:${contact.id}'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Invite code copied -- send it to ${contact.name} to enable push alerts')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const PageHeader(title: 'Safety & geofence'),
            Text(
              'Get alerted if this person leaves a safe area during a recording '
              'session. Not a diagnosis or a substitute for supervision.',
              style: TextStyle(color: p.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 20),
            Text('Safe zone', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: p.card(),
              child: _zone == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('No safe zone set yet.', style: TextStyle(color: p.textSecondary)),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _savingZone ? null : _setZoneToCurrentLocation,
                          child: Text(_savingZone ? 'Getting location...' : 'Set to current location'),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_zone!.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                        Text(
                          '${_zone!.latitude.toStringAsFixed(5)}, ${_zone!.longitude.toStringAsFixed(5)}',
                          style: TextStyle(color: p.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 12),
                        Text('Radius: ${_zone!.radiusMeters.round()} m', style: TextStyle(color: p.textSecondary)),
                        Slider(
                          value: _zone!.radiusMeters.clamp(50, 5000),
                          min: 50,
                          max: 5000,
                          divisions: 99,
                          onChanged: (v) => _setRadius(v),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _savingZone ? null : _setZoneToCurrentLocation,
                                child: const Text('Update to current location'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            TextButton(
                              onPressed: _removeZone,
                              child: const Text('Remove', style: TextStyle(color: AppColors.error)),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Family contacts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: p.text)),
                TextButton(onPressed: _addContact, child: const Text('Add')),
              ],
            ),
            const SizedBox(height: 8),
            if (_contacts.isEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: p.card(),
                child: Text('No family contacts added yet.', style: TextStyle(color: p.textSecondary)),
              )
            else
              Container(
                decoration: p.card(),
                child: Column(
                  children: [
                    for (var i = 0; i < _contacts.length; i++)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          border: i == _contacts.length - 1
                              ? null
                              : Border(bottom: BorderSide(color: p.border)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_contacts[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  Text(_contacts[i].email, style: TextStyle(color: p.textSecondary, fontSize: 12)),
                                  Text(
                                    _contacts[i].fcmToken == null
                                        ? 'Email only -- hasn\'t joined for push alerts'
                                        : 'Email + push alerts enabled',
                                    style: TextStyle(color: p.textTertiary, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.share_outlined),
                              tooltip: 'Copy invite code',
                              onPressed: () => _copyInviteCode(_contacts[i]),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error),
                              onPressed: () => _removeContact(_contacts[i]),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
