import 'dart:math';

import '../../../content/models/lesson.dart';
import '../../../content/models/lexeme.dart';
import '../../../learning/text/lexicon.dart';

/// A recurring difficulty the app can build focused practice for. The
/// rule ids match those recorded by the error detectors.
enum PracticeTopic {
  akkusativ('Akkusativ: einen / eine / ein', 'g_akkusativ'),
  perfektSein('Perfekt: haben mı, sein mi?', 'g_perfekt'),
  verbZweit('Fiil ikinci sırada', 'g_verbzweit');

  const PracticeTopic(this.titleTr, this.conceptId);
  final String titleTr;
  final String conceptId;

  static PracticeTopic? forRule(String ruleId) => switch (ruleId) {
        'akkusativ_der' || 'akkusativ_die' || 'akkusativ_das' => akkusativ,
        'perfekt_sein' => perfektSein,
        'verb_zweit' => verbZweit,
        _ => null,
      };

  static PracticeTopic? parse(String s) => PracticeTopic.values.where((t) => t.name == s).firstOrNull;
}

/// Builds short drills from curated data, so every generated answer key
/// is derived from validated lexicon fields (article, Perfekt auxiliary),
/// never invented. Deterministic for a given [seed].
class PracticeGenerator {
  PracticeGenerator(this.lexicon);
  final Lexicon lexicon;

  Lesson build(PracticeTopic topic, {int seed = 0, int size = 6}) {
    final rnd = Random(seed);
    final steps = <LessonStep>[
      GrammarStep('practice_${topic.name}#g', conceptId: topic.conceptId),
      ...switch (topic) {
        PracticeTopic.akkusativ => _akkusativ(rnd, size),
        PracticeTopic.perfektSein => _perfekt(rnd, size),
        PracticeTopic.verbZweit => _verbZweit(rnd, size),
      },
    ];
    return Lesson(
      id: 'practice_${topic.name}',
      titleTr: 'Odaklı alıştırma: ${topic.titleTr}',
      objectiveTr: 'Konuşmalarında tekrar eden bir hatayı hedefli olarak çalış.',
      minutes: 4,
      steps: steps,
    );
  }

  /// Nouns that fit every frame below naturally (food and everyday
  /// objects). People and n-declension nouns (der Nachbar → einen
  /// Nachbarn) are deliberately excluded.
  static const _akkNouns = {
    'kaffee', 'tee', 'saft', 'cappuccino', 'broetchen', 'brot', 'kuchen', 'croissant', 'brezel', 'apfel', 'banane',
    'tomate', 'ei', 'pizza', 'tisch', 'stuhl', 'lampe', 'tasche', 'handy', 'schluessel', 'buch', 'termin', 'flasche', 'tuete',
  };
  static const _akkFrames = [
    'Ich möchte ___ {n}, bitte.',
    'Wir brauchen ___ {n}.',
    'Ich nehme ___ {n}.',
    'Hast du ___ {n}?',
  ];

  List<LessonStep> _akkusativ(Random rnd, int size) {
    final nouns = lexicon.all
        .where((l) => _akkNouns.contains(l.id) && l.isNoun && l.article != null)
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    nouns.shuffle(rnd);
    // Make sure masculine nouns (where the form changes) are well represented.
    final masc = nouns.where((n) => n.article == 'der').take((size + 1) ~/ 2);
    final rest = nouns.where((n) => n.article != 'der').take(size ~/ 2);
    final picked = [...masc, ...rest]..shuffle(rnd);
    return [
      for (var i = 0; i < picked.length; i++)
        () {
          final n = picked[i];
          final frame = _akkFrames[i % _akkFrames.length];
          final answer = const {'der': 'einen', 'die': 'eine', 'das': 'ein'}[n.article]!;
          return ClozeStep(
            'practice_akk#$i',
            de: frame.replaceAll('{n}', n.lemma),
            tr: '"${n.lemma}" = ${n.tr}',
            answers: [answer],
            options: const ['ein', 'einen', 'eine'],
            explainTr: n.article == 'der'
                ? '${n.headword} eril; nesne olunca ein → einen.'
                : '${n.headword} ${n.article == 'die' ? 'dişil' : 'nötr'}; Akkusativ\'de değişmez: $answer.',
          );
        }(),
    ];
  }

  /// Complements per verb; the auxiliary always comes from the lexicon.
  static const _perfektBank = {
    'gehen': 'ins Kino',
    'fahren': 'nach Hamburg',
    'kommen': 'spät nach Hause',
    'bleiben': 'zu Hause',
    'aufstehen': 'um sechs Uhr',
    'kaufen': 'Brot',
    'essen': 'Pizza',
    'trinken': 'Kaffee',
    'lernen': 'Deutsch',
    'schlafen': 'lange',
    'arbeiten': 'viel',
    'schreiben': 'einen Brief',
  };

  List<LessonStep> _perfekt(Random rnd, int size) {
    final verbs = [
      for (final e in _perfektBank.entries)
        if (lexicon.byId(e.key) case final Lexeme l? when l.verb != null && l.verb!.participle != '—') (l, e.value),
    ]..shuffle(rnd);
    // Balance sein and haben verbs.
    final sein = verbs.where((v) => v.$1.verb!.auxiliary == 'sein').take((size + 1) ~/ 2);
    final haben = verbs.where((v) => v.$1.verb!.auxiliary == 'haben').take(size ~/ 2);
    final picked = [...sein, ...haben]..shuffle(rnd);
    return [
      for (var i = 0; i < picked.length; i++)
        () {
          final (l, rest) = picked[i];
          final v = l.verb!;
          final aux = v.auxiliary == 'sein' ? 'bin' : 'habe';
          return ClozeStep(
            'practice_perf#$i',
            de: 'Gestern ___ ich $rest ${v.participle}.',
            tr: '${l.lemma} (${l.tr}) – dün',
            answers: [aux],
            options: const ['habe', 'bin'],
            explainTr: v.auxiliary == 'sein'
                ? '${l.lemma} Perfekt\'te "sein" alır: ich bin ${v.participle}.'
                : '${l.lemma} Perfekt\'te "haben" alır: ich habe ${v.participle}.',
          );
        }(),
    ];
  }

  static const _v2Bank = [
    (['Heute', 'gehe', 'ich', 'ins', 'Kino'], 'Bugün sinemaya gidiyorum.'),
    (['Morgen', 'habe', 'ich', 'keine', 'Zeit'], 'Yarın vaktim yok.'),
    (['Am', 'Montag', 'arbeite', 'ich', 'im', 'Büro'], 'Pazartesi ofiste çalışıyorum.'),
    (['Dann', 'trinken', 'wir', 'einen', 'Kaffee'], 'Sonra bir kahve içiyoruz.'),
    (['Jetzt', 'wohne', 'ich', 'in', 'Berlin'], 'Şimdi Berlin\'de oturuyorum.'),
    (['Am', 'Samstag', 'kaufe', 'ich', 'ein'], 'Cumartesi alışveriş yapıyorum.'),
    (['Gestern', 'war', 'ich', 'müde'], 'Dün yorgundum.'),
  ];

  List<LessonStep> _verbZweit(Random rnd, int size) {
    final items = [..._v2Bank]..shuffle(rnd);
    return [
      for (var i = 0; i < items.length && i < size; i++)
        OrderStep(
          'practice_v2#$i',
          tr: items[i].$2,
          tokens: items[i].$1,
          answers: [items[i].$1.join(' ')],
          explainTr: 'Zaman ifadesi başta olsa bile çekimli fiil ikinci sırada, özne fiilden sonra.',
        ),
    ];
  }
}
