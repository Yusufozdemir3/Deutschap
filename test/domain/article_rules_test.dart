import 'package:deutschap/features/articles/domain/article_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';

void main() {
  final content = loadTestContent();

  test('rules match the longest ending and respect their limits', () {
    expect(ruleFor('Wohnung')!.article, 'die');
    expect(ruleFor('Brötchen')!.article, 'das');
    expect(ruleFor('Freundschaft')!.suffix, 'schaft');
    expect(ruleFor('Termin'), isNull, reason: '-in counts only for female persons');
    expect(ruleFor('Lehrerin', tr: 'öğretmen (kadın)')!.suffix, 'in');
    expect(ruleFor('Tee'), isNull);
    expect(ruleFor('Baum'), isNull, reason: 'too short a stem for -um');
  });

  test('"always" rules have no exceptions in the lexicon', () {
    for (final l in content.lexicon.all.where((l) => l.isNoun && l.article != null && !l.tags.contains('proper'))) {
      final r = ruleFor(l.lemma, tr: l.tr);
      if (r != null && r.strength == RuleStrength.always) expect(l.article, r.article, reason: l.headword);
    }
  });

  test('a round has ten nouns with at least one exception', () {
    final round = articleRound(content.lexicon, seed: 3);
    expect(round.length, 10);
    expect(round.where((q) => q.isException), isNotEmpty);
    expect(round.map((q) => q.lexeme.id).toSet().length, 10);
  });
}
