import 'package:flutter/material.dart';

import '../l10n.dart';
import 'favorites.dart';
import 'mix.dart';
import 'profile.dart';
import 'today.dart';
import 'wardrobe.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    const pages = [TodayScreen(), WardrobeScreen(), MixScreen(), FavoritesScreen(), ProfileScreen()];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.wb_sunny_outlined), selectedIcon: const Icon(Icons.wb_sunny), label: context.tr('tab_today')),
          NavigationDestination(icon: const Icon(Icons.checkroom_outlined), selectedIcon: const Icon(Icons.checkroom), label: context.tr('tab_wardrobe')),
          NavigationDestination(icon: const Icon(Icons.auto_awesome_outlined), selectedIcon: const Icon(Icons.auto_awesome), label: context.tr('tab_mix')),
          NavigationDestination(icon: const Icon(Icons.bookmark_border), selectedIcon: const Icon(Icons.bookmark), label: context.tr('tab_saved')),
          NavigationDestination(icon: const Icon(Icons.person_outline), selectedIcon: const Icon(Icons.person), label: context.tr('tab_profile')),
        ],
      ),
    );
  }
}
