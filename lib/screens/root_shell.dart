import 'package:flutter/material.dart';

import 'home_screen.dart';
import 'profile_screen.dart';
import 'records_screen.dart';
import 'trends_screen.dart';

/// Bottom-tab shell, mirroring `components/TabBar/TabBar.vue`'s 4 tabs
/// (home / trends / records / me).
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    TrendsScreen(),
    RecordsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.grid_view_outlined), label: 'Trends'),
          BottomNavigationBarItem(icon: Icon(Icons.list_alt_outlined), label: 'Records'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Me'),
        ],
      ),
    );
  }
}
