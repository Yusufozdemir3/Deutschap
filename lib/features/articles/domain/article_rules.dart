import 'dart:math';

import '../../../content/models/lexeme.dart';
import '../../../learning/text/lexicon.dart';

/// How far a rule can be trusted.
enum RuleStrength {
  always('her zaman'),
  mostly('çoğu zaman');

  const RuleStrength(this.labelTr);
  final String labelTr;
}

/// A noun ending that predicts the article.
class ArticleRule {
  const ArticleRule(this.suffix, this.article, this.strength, this.noteTr, {this.examples = const []});
  final String suffix;
  final String article;
  final RuleStrength strength;
  final String noteTr;
  final List<String> examples;

  String get titleTr => '-$suffix → $article (${strength.labelTr})';
}

/// The endings learners can rely on most. Ordered by suffix length when
/// matching, so "-schaft" wins over "-t".
const articleRules = <ArticleRule>[
  ArticleRule('ung', 'die', RuleStrength.always, '-ung ile biten isimler istisnasız dişildir.', examples: ['die Wohnung', 'die Zeitung', 'die Rechnung']),
  ArticleRule('heit', 'die', RuleStrength.always, 'Sıfattan türeyen soyut isimler.', examples: ['die Freiheit', 'die Gesundheit']),
  ArticleRule('keit', 'die', RuleStrength.always, 'Sıfattan türeyen soyut isimler.', examples: ['die Möglichkeit', 'die Schwierigkeit']),
  ArticleRule('schaft', 'die', RuleStrength.always, 'Topluluk ve durum bildiren isimler.', examples: ['die Freundschaft', 'die Nachbarschaft']),
  ArticleRule('ion', 'die', RuleStrength.always, 'Latince kökenli -ion/-tion/-sion isimleri.', examples: ['die Information', 'die Station']),
  ArticleRule('tät', 'die', RuleStrength.always, 'Latince kökenli soyut isimler.', examples: ['die Universität', 'die Qualität']),
  ArticleRule('ei', 'die', RuleStrength.mostly, 'Çoğu -ei ismi dişildir (das Ei hariç!).', examples: ['die Bäckerei', 'die Polizei']),
  ArticleRule('ie', 'die', RuleStrength.mostly, 'Yabancı kökenli -ie isimleri genelde dişil.', examples: ['die Familie', 'die Energie']),
  ArticleRule('ik', 'die', RuleStrength.mostly, 'Bilim ve alan adları.', examples: ['die Musik', 'die Politik']),
  ArticleRule('in', 'die', RuleStrength.mostly, 'Kadın meslek ve kişi isimleri (-in).', examples: ['die Lehrerin', 'die Ärztin']),
  ArticleRule('e', 'die', RuleStrength.mostly, '-e ile biten iki heceli isimlerin çoğu dişil; istisnalar: der Name, der Käse, das Auge …', examples: ['die Lampe', 'die Tasche']),
  ArticleRule('chen', 'das', RuleStrength.always, 'Küçültme eki: anlamı ne olursa olsun nötr (das Mädchen).', examples: ['das Brötchen', 'das Mädchen']),
  ArticleRule('lein', 'das', RuleStrength.always, 'Küçültme eki: nötr.', examples: ['das Fräulein']),
  ArticleRule('um', 'das', RuleStrength.mostly, 'Latince kökenli -um isimleri.', examples: ['das Museum', 'das Zentrum']),
  ArticleRule('ment', 'das', RuleStrength.mostly, 'Fransızca kökenli -ment isimleri.', examples: ['das Medikament', 'das Dokument']),
  ArticleRule('o', 'das', RuleStrength.mostly, 'Kısa yabancı kelimeler genelde nötr.', examples: ['das Auto', 'das Kino', 'das Büro']),
  ArticleRule('ling', 'der', RuleStrength.always, 'Kişi bildiren -ling isimleri.', examples: ['der Frühling', 'der Lehrling']),
  ArticleRule('ismus', 'der', RuleStrength.always, 'Akım ve düşünce isimleri.', examples: ['der Tourismus']),
  ArticleRule('ist', 'der', RuleStrength.mostly, 'Kişi bildiren -ist isimleri.', examples: ['der Polizist', 'der Tourist']),
  ArticleRule('or', 'der', RuleStrength.mostly, 'Latince kökenli kişi ve araç isimleri.', examples: ['der Motor', 'der Doktor']),
  ArticleRule('ig', 'der', RuleStrength.mostly, '-ig ile biten isimler.', examples: ['der Honig', 'der König']),
  ArticleRule('er', 'der', RuleStrength.mostly, 'Kişi ve araç bildiren -er isimleri sıkça eril; ama das Zimmer, die Mutter gibi çok istisna var.', examples: ['der Lehrer', 'der Computer']),
];

final List<ArticleRule> _bySuffixLength = [...articleRules]..sort((a, b) => b.suffix.length.compareTo(a.suffix.length));

/// The rule matching [lemma] (single word, at least three letters before
/// the ending), or null. "-in" only counts for female person nouns, which
/// the Turkish meaning marks with "(kadın)".
ArticleRule? ruleFor(String lemma, {String tr = ''}) {
  if (lemma.contains(' ')) return null;
  final w = lemma.toLowerCase();
  for (final r in _bySuffixLength) {
    if (!w.endsWith(r.suffix) || w.length - r.suffix.length < 3) continue;
    if (r.suffix == 'in' && !tr.contains('kadın')) continue;
    if (r.suffix == 'e' && w.endsWith('ee')) continue;
    return r;
  }
  return null;
}

class ArticleQuestion {
  const ArticleQuestion(this.lexeme, this.rule);
  final Lexeme lexeme;
  final ArticleRule rule;

  bool get isException => lexeme.article != rule.article;
}

/// A round of the game: nouns whose ending has a rule, mostly rule-following
/// ones plus a few exceptions so learners see where a rule stops.
List<ArticleQuestion> articleRound(Lexicon lexicon, {int size = 10, int seed = 0}) {
  final rnd = Random(seed);
  final all = [
    for (final l in lexicon.all)
      if (l.isNoun && l.article != null && !l.tags.contains('proper'))
        if (ruleFor(l.lemma, tr: l.tr) case final r?) ArticleQuestion(l, r),
  ]..sort((a, b) => a.lexeme.id.compareTo(b.lexeme.id));
  all.shuffle(rnd);
  final following = all.where((q) => !q.isException).toList();
  final exceptions = all.where((q) => q.isException).toList();
  final nExceptions = min(exceptions.length, max(1, size ~/ 5));
  final round = [...following.take(size - nExceptions), ...exceptions.take(nExceptions)]..shuffle(rnd);
  return round;
}
