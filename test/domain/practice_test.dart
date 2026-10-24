import 'package:deutschap/content/models/lesson.dart';
import 'package:deutschap/features/conversation/domain/error_detectors.dart';
import 'package:deutschap/features/conversation/domain/language_issue.dart';
import 'package:deutschap/features/home/domain/recommender.dart';
import 'package:deutschap/features/practice/domain/practice_generator.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';

void main() {
  final content = loadTestContent();
  final gen = PracticeGenerator(content.lexicon);
  final detectors = ErrorDetectors(content.lexicon);

  for (final topic in PracticeTopic.values) {
    group(topic.name, () {
      for (final seed in [1, 2, 3, 42]) {
        test('seed $seed produces valid, error-free items', () {
          final lesson = gen.build(topic, seed: seed);
          expect(lesson.gradedStepCount, greaterThanOrEqualTo(5));
          expect(content.grammar.containsKey(topic.conceptId), isTrue);
          for (final s in lesson.steps) {
            switch (s) {
              case ClozeStep(:final de, :final answers, :final options):
                expect('___'.allMatches(de).length, 1);
                expect(options, containsAll(answers));
                final filled = de.replaceFirst('___', answers.first);
                final errors = detectors.check(filled).where((i) => i.severity == IssueSeverity.error);
                expect(errors, isEmpty, reason: filled);
                // Every wrong option must actually be wrong for the detectors
                // that cover this pattern (where they apply).
                if (topic == PracticeTopic.akkusativ) {
                  for (final o in options.where((o) => !answers.contains(o))) {
                    final bad = de.replaceFirst('___', o);
                    expect(detectors.check(bad).any((i) => i.ruleId.startsWith('akkusativ')), isTrue, reason: bad);
                  }
                }
                if (topic == PracticeTopic.perfektSein && answers.first == 'bin') {
                  final bad = de.replaceFirst('___', 'habe');
                  expect(detectors.check(bad).any((i) => i.ruleId == 'perfekt_sein'), isTrue, reason: bad);
                }
              case OrderStep(:final tokens, :final answers):
                expect(answers.single.split(' ')..sort(), [...tokens]..sort());
                expect(detectors.check(answers.single), isEmpty, reason: answers.single);
              case GrammarStep():
                break;
              default:
                fail('unexpected step ${s.runtimeType}');
            }
          }
        });
      }
    });
  }

  test('akkusativ answers follow the lexicon gender', () {
    final lesson = gen.build(PracticeTopic.akkusativ, seed: 7);
    for (final s in lesson.steps.whereType<ClozeStep>()) {
      final lemma = RegExp(r'___ (\p{L}+)', unicode: true).firstMatch(s.de)!.group(1)!;
      final noun = content.lexicon.nounForm(lemma)!;
      expect(s.answers.single, const {'der': 'einen', 'die': 'eine', 'das': 'ein'}[noun.article]);
    }
  });

  test('rule ids map to topics', () {
    expect(PracticeTopic.forRule('akkusativ_der'), PracticeTopic.akkusativ);
    expect(PracticeTopic.forRule('perfekt_sein'), PracticeTopic.perfektSein);
    expect(PracticeTopic.forRule('noun_caps'), isNull);
  });

  test('a recurring error leads to a practice recommendation', () {
    const r = Recommender();
    final recs = r.recommend(const LearnerSnapshot(
      nextLesson: NamedRef('u2l1', 'Sayılar'),
      recurringIssue: ('akkusativ', 'Akkusativ', 3),
    ));
    expect(recs.first.kind, ActivityKind.practice);
    expect(recs.first.route, '/practice/akkusativ');
    final once = r.recommend(const LearnerSnapshot(nextLesson: NamedRef('u2l1', 'Sayılar'), recurringIssue: ('akkusativ', 'Akkusativ', 1)));
    expect(once.map((x) => x.kind), isNot(contains(ActivityKind.practice)), reason: 'one error is not a pattern');
  });
}
