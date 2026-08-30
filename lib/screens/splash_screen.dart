import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/auth_provider.dart';
import '../state/insole_provider.dart';
import '../theme/app_colors.dart';
import '../theme/app_palette.dart';

/// Mirrors `pages/splash/splash.vue`: boots local state, resolves whether
/// the user is already logged in, and routes accordingly.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _boot());
  }

  Future<void> _boot() async {
    final auth = context.read<AuthProvider>();
    final insole = context.read<InsoleProvider>();

    auth.onLoggedIn = (uid) {
      insole.hydrateFromCloud(uid);
    };

    await Future.wait([
      insole.init(),
      auth.loadLocalProfile(),
      FirebaseAuth.instance.authStateChanges().first.timeout(
            const Duration(seconds: 3),
            onTimeout: () => null,
          ),
    ]);

    if (!mounted) return;

    final isLoggedIn = FirebaseAuth.instance.currentUser != null;
    if (isLoggedIn) {
      await auth.hydrateProfile();
      await insole.hydrateFromCloud(auth.uid);
    }

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(isLoggedIn ? '/root' : '/login');
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_walk, color: AppColors.primary, size: 72),
            const SizedBox(height: 16),
            Text(
              'NurvoSync',
              style: TextStyle(color: p.text, fontSize: 28, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
