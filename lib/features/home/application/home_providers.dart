import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../content/models/scenario.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/data/progress_repository.dart';
import '../../vocabulary/domain/vocab_entry.dart';
import '../../vocabulary/domain/vocab_status.dart';
import '../domain/recommender.dart';

/// Something the learner left unfinished, newest first.
class ContinueItem {
  const ContinueItem({required this.title, required this.subtitle, required this.route, required this.at});
  final String title;
  final String subtitle;
  final String route;
  final DateTime at;
}

final continueItemProvider = Provider<ContinueItem?>((ref) {
  final content = ref.watch(contentProvider);
  final lessons = ref.watch(lessonProgressProvider).valueOrNull ?? const {};
  final episodes = ref.watch(episodeProgressProvider).valueOrNull ?? const {};
  final items = <ContinueItem>[];
  for (final p in lessons.values.where((p) => p.status == LessonStatus.inProgress)) {
    final l = content.lesson(p.lessonId);
    if (l == null || p.updatedAt == null) continue;
    items.add(ContinueItem(title: l.titleTr, subtitle: 'Ders · ${p.stepIndex + 1}/${l.steps.length}. adım', route: '/lesson/${l.id}', at: p.updatedAt!));
  }
  for (final p in episodes.values.where((p) => p.status == EpisodeStatus.inProgress)) {
    final e = content.episode(p.episodeId);
    if (e == null || p.updatedAt == null) continue;
    items.add(ContinueItem(title: e.title, subtitle: 'Hikâye · ${content.storyOfEpisode(e.id)?.title ?? ''}', route: '/episode/${e.id}', at: p.updatedAt!));
  }
  items.sort((a, b) => b.at.compareTo(a.at));
  return items.firstOrNull;
});

class HomeData {
  const HomeData({required this.recommendations, required this.productionGap});
  final List<Recommendation> recommendations;
  final List<VocabEntry> productionGap;
}

/// Picks the scenario that best rehearses [lexemeIds]; falls back to the
/// scenario linked to the next episode or the first not yet completed.
Scenario? practiceScenarioFor(List<Scenario> all, Set<String> lexemeIds, {String? preferredId, Set<String> completed = const {}}) {
  Scenario? best;
  var bestOverlap = 0;
  for (final s in all) {
    final o = s.vocab.where(lexemeIds.contains).length;
    if (o > bestOverlap) {
      best = s;
      bestOverlap = o;
    }
  }
  if (best != null) return best;
  if (preferredId != null) {
    for (final s in all) {
      if (s.id == preferredId && !completed.contains(s.id)) return s;
    }
  }
  for (final s in all) {
    if (!completed.contains(s.id)) return s;
  }
  return null;
}

final homeDataProvider = FutureProvider<HomeData>((ref) async {
  ref.watch(dataRevisionProvider);
  final content = ref.watch(contentProvider);
  final vocab = ref.watch(vocabRepositoryProvider);
  final progress = ref.watch(progressRepositoryProvider);
  final nextLesson = ref.watch(nextLessonProvider);
  final nextEpisode = ref.watch(nextEpisodeProvider);
  final completed = await ref.watch(completedScenariosProvider.future);

  final due = await vocab.dueCount();
  final unreviewed = await vocab.unreviewedCount();
  final counts = await vocab.statusCounts();
  final gap = await vocab.productionGap();
  final recent = await progress.recentActivity(limit: 4);
  final scenario = practiceScenarioFor(
    content.scenarios,
    {for (final e in gap) ?e.lexemeId},
    preferredId: nextEpisode?.scenarioId,
    completed: completed,
  );

  final recs = const Recommender().recommend(LearnerSnapshot(
    dueCards: due,
    unreviewedSaved: unreviewed,
    needsReinforcement: counts[VocabStatus.needsReinforcement] ?? 0,
    productionGap: gap.length,
    nextLesson: nextLesson == null ? null : NamedRef(nextLesson.id, nextLesson.titleTr, minutes: nextLesson.minutes),
    nextEpisode: nextEpisode == null ? null : NamedRef(nextEpisode.id, '${nextEpisode.title} · ${nextEpisode.titleTr}', minutes: nextEpisode.minutes),
    practiceScenario: scenario == null ? null : NamedRef(scenario.id, scenario.titleTr, minutes: 5),
    lastKinds: [for (final a in recent) a.kind],
    totalEntries: counts.values.fold(0, (a, b) => a + b),
  ));
  // Point production-gap practice at the exact words.
  final withFocus = [
    for (final r in recs)
      if (r.kind == ActivityKind.scenario && gap.isNotEmpty)
        Recommendation(kind: r.kind, titleTr: r.titleTr, reasonTr: r.reasonTr, route: '${r.route}?focus=${gap.map((e) => e.id).join(',')}', minutes: r.minutes)
      else
        r,
  ];
  return HomeData(recommendations: withFocus, productionGap: gap);
});
