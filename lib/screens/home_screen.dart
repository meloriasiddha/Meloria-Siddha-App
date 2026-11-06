import 'package:flutter/material.dart';

import '../services/db.dart';
import '../widgets/common.dart';
import 'more_screen.dart';
import 'patients_screen.dart';
import 'stock_screen.dart';
import 'today_screen.dart';

/// Holds who is signed in, so any screen can check doctor vs staff.
class Session {
  static String name = '';
  static String role = 'staff';
  static bool get isDoctor => role == 'doctor';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final p = await Db.myProfile();
      if (p == null) {
        _error = 'This login is not registered as doctor or staff.\n'
            'Ask the admin to add it (README, step 4).';
      } else {
        Session.name = str(p['full_name']);
        Session.role = str(p['role']);
      }
    } catch (e) {
      _error = 'Could not load your profile: $e';
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_error != null) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const BrandMark(size: 64),
                const SizedBox(height: 24),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                OutlinedButton(onPressed: Db.signOut, child: const Text('Sign out')),
              ],
            ),
          ),
        ),
      );
    }

    final pages = [
      const TodayScreen(),
      const PatientsScreen(),
      const StockScreen(),
      const MoreScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'Today'),
          NavigationDestination(
              icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people), label: 'Patients'),
          NavigationDestination(
              icon: Icon(Icons.inventory_2_outlined),
              selectedIcon: Icon(Icons.inventory_2),
              label: 'Stock'),
          NavigationDestination(
              icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
