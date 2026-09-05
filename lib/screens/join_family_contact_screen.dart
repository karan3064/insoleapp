import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/fcm_token_service.dart';
import '../services/geofence_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';
import '../widgets/page_header.dart';

/// Where a family member registers their own device for geofence-breach
/// push alerts, without needing a full NurvoSync account of their own --
/// reachable from the login screen. The invite code (copied from
/// `SafetyScreen`) is `"<patientUid>:<contactId>"`; entering it here signs
/// this device in anonymously (just enough for Firestore to attribute the
/// write -- see `GeofenceService`'s doc comment for the security rule this
/// needs) and attaches this device's FCM token to that contact doc.
class JoinFamilyContactScreen extends StatefulWidget {
  const JoinFamilyContactScreen({super.key});

  @override
  State<JoinFamilyContactScreen> createState() => _JoinFamilyContactScreenState();
}

class _JoinFamilyContactScreenState extends State<JoinFamilyContactScreen> {
  final _codeController = TextEditingController();
  final _geofenceService = GeofenceService();
  final _fcmService = FcmTokenService();
  bool _submitting = false;
  String? _error;
  bool _joined = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final raw = _codeController.text.trim();
    final parts = raw.split(':');
    if (parts.length != 2 || parts[0].isEmpty || parts[1].isEmpty) {
      setState(() => _error = 'That doesn\'t look like a valid invite code.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      if (FirebaseAuth.instance.currentUser == null) {
        await FirebaseAuth.instance.signInAnonymously();
      }

      final token = await _fcmService.requestToken();
      if (token == null) {
        setState(() {
          _error = 'Notification permission is needed to receive push alerts.';
          _submitting = false;
        });
        return;
      }

      await _geofenceService.registerContactToken(
        patientUid: parts[0],
        contactId: parts[1],
        fcmToken: token,
      );

      if (!mounted) return;
      setState(() {
        _joined = true;
        _submitting = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Could not register this device: $e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const PageHeader(title: 'Join as a family contact'),
              Text(
                'Enter the invite code shared with you to get alerted on this '
                'phone if they leave their safe zone during a recording session.',
                style: TextStyle(color: p.textSecondary),
              ),
              const SizedBox(height: 20),
              if (_joined) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: p.card(),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: AppColors.success),
                      const SizedBox(width: 12),
                      Expanded(child: Text('This device is registered for alerts.', style: TextStyle(color: p.text))),
                    ],
                  ),
                ),
              ] else ...[
                TextField(
                  controller: _codeController,
                  decoration: const InputDecoration(labelText: 'Invite code'),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: AppColors.error)),
                  const SizedBox(height: 12),
                ],
                ElevatedButton(
                  onPressed: _submitting ? null : _join,
                  child: Text(_submitting ? 'Joining...' : 'Join'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
