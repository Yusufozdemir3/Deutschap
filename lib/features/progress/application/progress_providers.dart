import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../content/models/lesson.dart';
import '../../../content/models/story.dart';
import '../../../core/clock.dart';
import '../../reading/data/reading_repository.dart';
import '../data/progress_repository.dart';
import '../data/stats_repository.dart';

final lessonProgressProvider = FutureProvider<Map<String, LessonProgress>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(progressRepositoryProvider).lessonProgress();
});

final episodeProgressProvider = FutureProvider<Map<String, EpisodeProgress>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(progressRepositoryProvider).episodeProgress();
});

final completedScenariosProvider = FutureProvider<Set<String>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(progressRepositoryProvider).completedScenarioIds();
});

final pastedDocsProvider = FutureProvider<List<ReadingDoc>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(readingRepositoryProvider).pastedDocs();
});

final builtinPositionsProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(readingRepositoryProvider).builtinPositions();
});

final statsProvider = FutureProvider<LearningStats>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(statsRepositoryProvider).load();
});

/// Days this week with any learning, for the flexible weekly goal.
final activeDaysThisWeekProvider = FutureProvider<Set<DateTime>>((ref) {
  ref.watch(dataRevisionProvider);
  final now = ref.watch(clockProvider)();
  return ref.watch(progressRepositoryProvider).activeDays(startOfWeek(now));
});

/// First lesson in curriculum order that is not completed.
final nextLessonProvider = Provider<Lesson?>((ref) {
  final progress = ref.watch(lessonProgressProvider).valueOrNull ?? const {};
  for (final l in ref.watch(contentProvider).orderedLessons) {
    if (progress[l.id]?.status != LessonStatus.completed) return l;
  }
  return null;
});

/// The episode the learner should play next in each story (in progress
/// first, otherwise the first not completed), at the learner's level.
final nextEpisodeProvider = Provider<Episode?>((ref) {
  final content = ref.watch(contentProvider);
  final level = ref.watch(profileProvider).valueOrNull?.level ?? 'A1';
  final progress = ref.watch(episodeProgressProvider).valueOrNull ?? const {};
  for (final s in content.stories) {
    for (final n in s.episodeNumbers) {
      final e = s.variantFor(n, level);
      if (progress[e.id]?.status != EpisodeStatus.completed) return e;
    }
  }
  return null;
});
