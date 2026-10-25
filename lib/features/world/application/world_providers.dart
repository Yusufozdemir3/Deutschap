import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/clock.dart';
import '../domain/world_progress.dart';

final progressFactsProvider = FutureProvider<ProgressFacts>((ref) {
  ref.watch(dataRevisionProvider);
  final content = ref.watch(contentProvider);
  return ref.watch(statsRepositoryProvider).loadFacts(episodeNumber: (id) => content.episode(id)?.number);
});

final milestoneStatusProvider = FutureProvider<List<MilestoneStatus>>((ref) async {
  final facts = await ref.watch(progressFactsProvider.future);
  final content = ref.watch(contentProvider);
  return evaluateMilestones(facts, places: content.places, clues: content.clues);
});

/// Earned milestones the learner has not been shown yet. Marking them
/// seen is explicit, so a celebration appears once, never repeatedly.
const _seenKey = 'milestones_seen';

final unseenMilestonesProvider = FutureProvider<List<MilestoneStatus>>((ref) async {
  final all = await ref.watch(milestoneStatusProvider.future);
  final seen = (await ref.watch(kvStoreProvider).getJson(_seenKey)).keys.toSet();
  return [for (final m in all) if (m.earned && !seen.contains(m.milestone.id)) m];
});

Future<void> markMilestonesSeen(WidgetRef ref, Iterable<String> ids) async {
  final kv = ref.read(kvStoreProvider);
  final seen = await kv.getJson(_seenKey);
  final now = ref.read(clockProvider)().toIso8601String();
  for (final id in ids) {
    seen.putIfAbsent(id, () => now);
  }
  await kv.setJson(_seenKey, seen);
  ref.invalidate(unseenMilestonesProvider);
}
