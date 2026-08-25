import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/root_shell.dart';
import 'screens/signup_screen.dart';
import 'screens/splash_screen.dart';
import 'state/auth_provider.dart';
import 'state/ble_provider.dart';
import 'state/insole_provider.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    // Falls through to local-only mode until `flutterfire configure` has
    // been run -- see lib/firebase_options.dart.
    debugPrint('Firebase init skipped/failed: $e');
  }

  runApp(const SoleSyncApp());
}

class SoleSyncApp extends StatelessWidget {
  const SoleSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => InsoleProvider()),
        ChangeNotifierProvider(create: (_) => BleProvider()),
      ],
      child: MaterialApp(
        title: 'SoleSync',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.dark,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.dark,
        initialRoute: '/splash',
        routes: {
          '/splash': (_) => const SplashScreen(),
          '/login': (_) => const LoginScreen(),
          '/signup': (_) => const SignupScreen(),
          '/root': (_) => const RootShell(),
        },
      ),
    );
  }
}
