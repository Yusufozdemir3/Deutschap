import 'package:deutschap/features/vocabulary/domain/vocab_status.dart';
import 'package:deutschap/features/world/domain/world_progress.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';

void main() {
  final content = loadTestContent();
  final places = content.places;
  final clues = content.clues;

  test('a new learner has nothing unlocked, revealed or earned', () {
    const f = ProgressFacts();
    expect(places.where((p) => isUnlocked(p, f)), isEmpty);
    expect(clues.map((c) => clueState(c, f)).toSet(), {ClueState.hidden});
    expect(evaluateMilestones(f, places: places, clues: clues).where((m) => m.earned), isEmpty);
  });

  test('places unlock by any of their conditions, including any episode variant', () {
    final wg = places.firstWhere((p) => p.id == 'wg');
    expect(isUnlocked(wg, const ProgressFacts(episodeNumbers: {1})), isTrue);
    expect(isUnlocked(wg, const ProgressFacts(lessons: {'u1l2'})), isTrue);
    final cafe = places.firstWhere((p) => p.id == 'cafe');
    expect(isUnlocked(cafe, const ProgressFacts(scenarios: {'cafe'})), isTrue);
    expect(isUnlocked(cafe, const ProgressFacts(scenarios: {'termin'})), isFalse);
  });

  test('clues are revealed by the story and solved only by unaided recall of all their words', () {
    final c = clues.firstWhere((c) => c.id == 'c_postkarte');
    expect(clueState(c, const ProgressFacts(episodeNumbers: {1})), ClueState.revealed);
    expect(clueState(c, ProgressFacts(episodeNumbers: const {1}, recalledLexemes: {c.lexemes.first})), ClueState.revealed);
    expect(clueState(c, ProgressFacts(episodeNumbers: const {1}, recalledLexemes: {...c.lexemes})), ClueState.solved);
    expect(clueState(c, ProgressFacts(recalledLexemes: {...c.lexemes})), ClueState.hidden, reason: 'words alone do not reveal the story');
  });

  test('milestones track real progress with targets from content', () {
    final f = ProgressFacts(
      lessons: {for (var i = 0; i < 12; i++) 'l$i'},
      scenarios: const {'baeckerei'},
      unaidedRecalls: 40,
      statusCounts: const {VocabStatus.familiar: 20, VocabStatus.temporarilyMastered: 6},
    );
    final byId = {for (final m in evaluateMilestones(f, places: places, clues: clues)) m.milestone.id: m};
    expect(byId['first_order']!.earned, isTrue);
    expect(byId['path_half']!.earned, isTrue);
    expect(byId['path_done']!.earned, isFalse);
    expect(byId['recall_100']!.current, 40);
    expect(byId['familiar_25']!.earned, isTrue, reason: '20 familiar + 6 mastered = 26 at familiar or better');
    expect(byId['mastered_10']!.current, 6);
    expect(byId['explorer']!.target, places.length);
    expect(byId['detective']!.target, clues.length);
  });

  test('every milestone is reachable with the shipped content', () {
    final f = ProgressFacts(
      lessons: {for (final l in content.orderedLessons) l.id},
      episodeNumbers: {for (final s in content.stories) ...s.episodeNumbers},
      scenarios: {for (final s in content.scenarios) s.id},
      readings: {for (final r in content.readings) r.id},
      unaidedRecalls: 1000,
      unaidedArticles: 100,
      unaidedProductions: 100,
      statusCounts: const {VocabStatus.temporarilyMastered: 100},
      recalledLexemes: {for (final c in clues) ...c.lexemes},
    );
    final notEarned = [
      for (final m in evaluateMilestones(f, places: places, clues: clues))
        if (!m.earned) m.milestone.id,
    ];
    expect(notEarned, isEmpty);
  });
}
