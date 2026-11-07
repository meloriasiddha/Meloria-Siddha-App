import 'package:flutter/material.dart';

import 'bookings_screen.dart';
import 'home_screen.dart';
import 'profile_screen.dart';
import 'records_screen.dart';
import 'tracker_screen.dart';

/// Bottom navigation: Home · Bookings · Tracker · Records · Profile.
class Shell extends StatefulWidget {
  const Shell({super.key});

  /// Switch tab from anywhere (e.g. Home → Bookings).
  static final tab = ValueNotifier<int>(0);

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: Shell.tab,
      builder: (_, i, __) => Scaffold(
        body: IndexedStack(index: i, children: const [
          HomeScreen(),
          BookingsScreen(),
          TrackerScreen(),
          RecordsScreen(),
          ProfileScreen(),
        ]),
        bottomNavigationBar: NavigationBar(
          selectedIndex: i,
          onDestinationSelected: (v) => Shell.tab.value = v,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.calendar_today_outlined), selectedIcon: Icon(Icons.calendar_today), label: 'Bookings'),
            NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Tracker'),
            NavigationDestination(
                icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description), label: 'Records'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
