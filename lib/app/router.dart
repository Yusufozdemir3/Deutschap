import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/conversation/presentation/scenario_screen.dart';
import '../features/discover/presentation/discover_screen.dart';
import '../features/grammar/presentation/grammar_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/learn/presentation/learn_screen.dart';
import '../features/lesson/presentation/lesson_screen.dart';
import '../features/onboarding/presentation/onboarding_screen.dart';
import '../features/onboarding/presentation/placement_screen.dart';
import '../features/profile/presentation/profile_screen.dart';
import '../features/progress/presentation/progress_screen.dart';
import '../features/reading/presentation/paste_text_screen.dart';
import '../features/reading/presentation/reader_screen.dart';
import '../features/review/presentation/review_screen.dart';
import '../features/settings/presentation/notifications_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/stories/presentation/episode_screen.dart';
import '../features/stories/presentation/story_screen.dart';
import '../features/vocabulary/presentation/collections_screen.dart';
import '../features/vocabulary/presentation/library_screen.dart';
import '../features/vocabulary/presentation/word_detail_screen.dart';
import 'providers.dart';
import 'shell.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  final onboarded = ValueNotifier<bool>(ref.read(profileProvider).valueOrNull?.onboarded ?? false);
  ref.listen(profileProvider, (_, next) => onboarded.value = next.valueOrNull?.onboarded ?? false);
  ref.onDispose(onboarded.dispose);

  GoRoute page(String path, Widget Function(GoRouterState s) build) =>
      GoRoute(path: path, parentNavigatorKey: _rootKey, builder: (_, s) => build(s));

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/heute',
    refreshListenable: onboarded,
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final inOnboarding = loc.startsWith('/onboarding');
      if (!onboarded.value && !inOnboarding) return '/onboarding';
      if (onboarded.value && loc == '/onboarding') return '/heute';
      return null;
    },
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/onboarding/placement', builder: (_, _) => const PlacementScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/heute', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/lernen',
              builder: (_, s) => LearnScreen(initialTab: LearnTab.fromQuery(s.uri.queryParameters['tab'])),
            ),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/entdecken', builder: (_, _) => const DiscoverScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/wortschatz', builder: (_, _) => const LibraryScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profil', builder: (_, _) => const ProfileScreen())]),
        ],
      ),
      page('/lesson/:id', (s) => LessonScreen(lessonId: s.pathParameters['id']!)),
      page('/grammar/:id', (s) => GrammarScreen(conceptId: s.pathParameters['id']!)),
      page('/story/:id', (s) => StoryScreen(storyId: s.pathParameters['id']!)),
      page('/episode/:id', (s) => EpisodeScreen(episodeId: s.pathParameters['id']!)),
      page('/scenario/:id', (s) => ScenarioScreen(scenarioId: s.pathParameters['id']!, focusEntries: s.uri.queryParameters['focus'])),
      page('/reader/:id', (s) => ReaderScreen(docId: s.pathParameters['id']!)),
      page('/paste', (_) => const PasteTextScreen()),
      page('/review', (s) => ReviewScreen(size: int.tryParse(s.uri.queryParameters['n'] ?? '') ?? 10)),
      page('/word/:id', (s) => WordDetailScreen(entryId: s.pathParameters['id']!)),
      page('/lexeme/:id', (s) => LexemeDetailScreen(lexemeId: s.pathParameters['id']!)),
      page('/collections', (_) => const CollectionsScreen()),
      page('/progress', (_) => const ProgressScreen()),
      page('/settings', (_) => const SettingsScreen()),
      page('/settings/notifications', (_) => const NotificationsScreen()),
    ],
  );
});

class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Bu sayfa bulunamadı.'),
            const SizedBox(height: 12),
            FilledButton(onPressed: () => context.go('/heute'), child: const Text('Ana sayfaya dön')),
          ]),
        ),
      );
}
