import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers.dart';

/// Bottom navigation: five destinations, nothing more. Conversation,
/// reading and stories live under "Lernen" to keep the bar calm.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final due = ref.watch(dueCountProvider).valueOrNull ?? 0;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.wb_sunny_outlined), selectedIcon: Icon(Icons.wb_sunny_rounded), label: 'Bugün'),
          const NavigationDestination(icon: Icon(Icons.route_outlined), selectedIcon: Icon(Icons.route_rounded), label: 'Öğren'),
          const NavigationDestination(icon: Icon(Icons.explore_outlined), selectedIcon: Icon(Icons.explore_rounded), label: 'Keşfet'),
          NavigationDestination(
            icon: Badge(isLabelVisible: due > 0, label: Text('$due'), child: const Icon(Icons.auto_stories_outlined)),
            selectedIcon: Badge(isLabelVisible: due > 0, label: Text('$due'), child: const Icon(Icons.auto_stories_rounded)),
            label: 'Kelimeler',
            tooltip: due > 0 ? 'Kelimeler, $due tekrar bekliyor' : 'Kelimeler',
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Profil'),
        ],
      ),
    );
  }
}
