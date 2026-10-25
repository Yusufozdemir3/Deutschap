import 'package:deutschap/content/models/lesson.dart';
import 'package:deutschap/features/drill/domain/vocab_drill.dart';
import 'package:deutschap/learning/answer_checker.dart';
import 'package:deutschap/ui/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';

void main() {
  final content = loadTestContent();
  final gen = VocabDrillGenerator(content.lexicon);
  final words = (content.lexicon.all.toList()..sort((a, b) => a.id.compareTo(b.id)));

  for (final mode in DrillMode.values) {
    for (final seed in [1, 7, 99]) {
      test('${mode.name} seed $seed builds valid steps', () {
        final pool = [...words]..shuffle();
        final lesson = gen.build(pool, mode: mode, size: 12, seed: seed);
        expect(lesson.gradedStepCount, greaterThanOrEqualTo(2));
        for (final s in lesson.steps) {
          switch (s) {
            case ChoiceStep(:final options, :final answers):
              expect(options.toSet().length, options.length, reason: s.id);
              expect(answers.single, inInclusiveRange(0, options.length - 1));
              expect(options.length, greaterThanOrEqualTo(3), reason: s.id);
            case ListenStep(:final options, :final answers):
              expect(options.toSet().length, options.length);
              expect(answers.single, inInclusiveRange(0, options.length - 1));
            case ArticleStep(:final lexemeId):
              expect(content.lexicon.byId(lexemeId)!.article, isNotNull);
            case ClozeStep(:final de, :final answers):
              expect('___'.allMatches(de).length, 1, reason: de);
              expect(answers, isNotEmpty);
            case TranslateStep(:final answers):
              expect(checkAnswer(answers.first, answers).verdict, AnswerVerdict.correct);
            case MatchStep(:final pairs):
              expect(pairs.length, greaterThanOrEqualTo(3));
              expect(pairs.map((p) => p.tr).toSet().length, pairs.length);
            default:
              fail('unexpected step ${s.runtimeType}');
          }
          if (s is! MatchStep) expect(VocabDrillGenerator.describe(s, lesson), isNotNull, reason: s.id);
        }
      });
    }
  }

  test('describe maps steps back to the tested word and mode', () {
    final lesson = gen.build(words, mode: DrillMode.article, size: 5, seed: 3);
    for (final s in lesson.steps) {
      final (id, mode) = VocabDrillGenerator.describe(s, lesson)!;
      expect(mode, DrillMode.article);
      expect((s as ArticleStep).lexemeId, id);
    }
  });

  test('plural distractors never contain the correct plural', () {
    for (final l in words.where(VocabDrillGenerator.hasPlural)) {
      final wrong = VocabDrillGenerator.pluralDistractors(l);
      expect(wrong, isNot(contains(l.plural)), reason: l.id);
      expect(wrong.toSet().length, wrong.length);
    }
    final tisch = content.lexicon.byId('tisch')!;
    expect(VocabDrillGenerator.pluralDistractors(tisch), containsAll(['die Tischen', 'die Tischs']));
  });

  test('context blanks a real form from an example', () {
    final c = gen.contextFor(content.lexicon.byId('gehen')!);
    expect(c, isNotNull);
    expect(c!.$1.replaceFirst('___', c.$2), content.lexicon.byId('gehen')!.examples.first.de);
  });

  test('distractor meanings do not overlap the answer', () {
    final lesson = gen.build(words, mode: DrillMode.meaning, size: 30, seed: 5);
    for (final s in lesson.steps.cast<ChoiceStep>()) {
      final answer = s.options[s.answers.single];
      for (final o in s.options.where((o) => o != answer)) {
        expect(o, isNot(answer));
      }
    }
  });

  test('spec round-trips through the route query', () {
    const spec = DrillSpec(source: 'tag:essen', mode: DrillMode.plural, size: 20);
    final back = DrillSpec.fromQuery(Uri.parse('/drill/run?${spec.query}').queryParameters);
    expect(back.source, 'tag:essen');
    expect(back.mode, DrillMode.plural);
    expect(back.size, 20);
  });

  test('option order is a stable permutation that moves first answers around', () {
    expect(optionOrder(4, 'x#1'), optionOrder(4, 'x#1'));
    expect(optionOrder(4, 'x#1').toSet(), {0, 1, 2, 3});
    final firstPositions = {for (var i = 0; i < 40; i++) optionOrder(3, 'step#$i').indexOf(0)};
    expect(firstPositions, {0, 1, 2});
  });
}
