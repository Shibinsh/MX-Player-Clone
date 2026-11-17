import 'package:flutter/material.dart';

import 'local_screen.dart';
import 'me_screen.dart';
import 'music_screen.dart';
import 'transfer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _index = 0;
  final Set<int> _loadedTabs = {0};

  void _selectTab(int index) {
    setState(() {
      _index = index;
      _loadedTabs.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      LocalScreen(onTabRequested: _selectTab),
      _loadedTabs.contains(1) ? const MusicScreen() : const SizedBox.shrink(),
      _loadedTabs.contains(2)
          ? const TransferScreen()
          : const SizedBox.shrink(),
      _loadedTabs.contains(3) ? const MeScreen() : const SizedBox.shrink(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        height: 72,
        indicatorColor: Colors.transparent,
        onDestinationSelected: _selectTab,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.folder), label: 'Local'),
          NavigationDestination(icon: Icon(Icons.music_note), label: 'Music'),
          NavigationDestination(
              icon: Icon(Icons.mobile_screen_share), label: 'Transfer'),
          NavigationDestination(icon: Icon(Icons.account_circle), label: 'Me'),
        ],
      ),
    );
  }
}
