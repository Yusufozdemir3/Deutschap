import 'dart:math';

import '../../../content/models/lesson.dart';
import '../../../content/models/lexeme.dart';
import '../../../learning/text/lexicon.dart';

/// Kinds of vocabulary exercise. Every answer key comes from validated
/// lexicon fields (meaning, article, plural, examples), never invented.
enum DrillMode {
  mixed('Karışık', 'Her kelime için farklı bir alıştırma türü'),
  meaning('Anlamı seç', 'Almanca kelimeyi gör, Türkçe anlamını seç'),
  reverse('Almancasını seç', 'Türkçe anlamı gör, Almanca kelimeyi seç'),
  article('der · die · das', 'İsimlerin artikelini seç'),
  plural('Çoğul', 'İsimlerin çoğul biçimini seç'),
  spell('Yaz', 'Türkçeden Almancasını yaz (isimler artikeliyle)'),
  listen('Dinle', 'Kelimeyi dinle, anlamını seç'),
  context('Cümlede', 'Örnek cümledeki boşluğa doğru biçimi yaz'),
  conjugate('Fiil çekimi', 'Fiili verilen kişiye göre çek (du fährst, er nimmt …)'),
  perfekt('Perfekt', 'Fiilin Perfekt biçimini seç (ist gegangen, hat gemacht)'),
  match('Eşleştir', 'Kelimeleri anlamlarıyla eşleştir');

  const DrillMode(this.labelTr, this.descriptionTr);
  final String labelTr;
  final String descriptionTr;

  static DrillMode parse(String? s) => DrillMode.values.firstWhere((m) => m.name == s, orElse: () => DrillMode.mixed);
}

/// What a drill is built from, encoded for routes: `saved`, `weak`,
/// `level:A2`, `unit:a1_u3`, `tag:essen`.
class DrillSpec {
  const DrillSpec({required this.source, this.mode = DrillMode.mixed, this.size = 10});
  final String source;
  final DrillMode mode;
  final int size;

  String get query => 'src=${Uri.encodeComponent(source)}&mode=${mode.name}&n=$size';

  static DrillSpec fromQuery(Map<String, String> q) => DrillSpec(
        source: q['src'] ?? 'saved',
        mode: DrillMode.parse(q['mode']),
        size: (int.tryParse(q['n'] ?? '') ?? 10).clamp(4, 30),
      );
}

/// Item ids recorded for drill attempts: `lexemeId:mode`.
String drillItemId(String lexemeId, DrillMode mode) => '$lexemeId:${mode.name}';
String lexemeOfDrillItem(String itemId) => itemId.split(':').first;

class VocabDrillGenerator {
  VocabDrillGenerator(this.lexicon);
  final Lexicon lexicon;

  static bool _usable(Lexeme l) => !l.tags.contains('proper') && l.tr.trim().isNotEmpty;
  static bool hasArticle(Lexeme l) => l.isNoun && l.article != null && _usable(l);
  static bool hasPlural(Lexeme l) => hasArticle(l) && l.plural != null && l.plural!.startsWith('die ') && !l.plural!.contains('/');
  static bool spellable(Lexeme l) => _usable(l) && l.lemma.length <= 22 && l.pos != PartOfSpeech.number;
  static bool conjugatable(Lexeme l) => (l.verb?.presentForms.length ?? 0) >= 6;

  /// Verbs where both auxiliaries are correct in common use ("Ich habe das
  /// Auto gefahren"), so a wrong-auxiliary distractor would not be wrong.
  static const _bothAux = {'fahren', 'fliegen', 'schwimmen', 'reiten', 'ziehen', 'umziehen', 'stehen', 'liegen', 'sitzen'};
  static bool hasPerfekt(Lexeme l) =>
      l.verb != null && l.verb!.participle != '—' && !l.isMultiWord && !_bothAux.contains(l.id) && const {'haben', 'sein'}.contains(l.verb!.auxiliary);

  /// Whether [mode] can make an exercise for [l].
  bool supports(Lexeme l, DrillMode mode) => switch (mode) {
        DrillMode.mixed || DrillMode.meaning || DrillMode.reverse || DrillMode.listen || DrillMode.match => _usable(l),
        DrillMode.article => hasArticle(l),
        DrillMode.plural => hasPlural(l),
        DrillMode.spell => spellable(l),
        DrillMode.context => _usable(l) && contextFor(l) != null,
        DrillMode.conjugate => conjugatable(l),
        DrillMode.perfekt => hasPerfekt(l),
      };

  /// Builds a drill over [words] (already chosen and ordered by priority:
  /// the first ones are used when there are more than [size]).
  Lesson build(List<Lexeme> words, {required DrillMode mode, int size = 10, int seed = 0, String title = 'Kelime antrenmanı'}) {
    final rnd = Random(seed);
    final usable = words.where((w) => supports(w, mode)).take(size).toList()..shuffle(rnd);
    final steps = <LessonStep>[];
    if (mode == DrillMode.match) {
      for (var i = 0; i < usable.length; i += 5) {
        final m = _match(usable.skip(i).take(5).toList(), 'drill#m$i');
        if (m != null) steps.add(m);
      }
    } else {
      if (mode == DrillMode.mixed && usable.length >= 6) {
        final m = _match(usable.take(5).toList(), 'drill#m');
        if (m != null) steps.add(m);
      }
      for (var i = 0; i < usable.length; i++) {
        final l = usable[i];
        final m = mode == DrillMode.mixed ? _pickMode(l, rnd, i) : mode;
        final step = _step(l, m, rnd, 'drill#$i');
        if (step != null) steps.add(step);
      }
    }
    return Lesson(
      id: 'drill',
      titleTr: title,
      objectiveTr: mode.descriptionTr,
      minutes: max(2, (steps.length * 0.5).round()),
      vocab: [for (final w in usable) w.id],
      steps: steps,
    );
  }

  /// The lexeme and mode a drill step tests, for recording attempts.
  static (String lexemeId, DrillMode mode)? describe(LessonStep s, Lesson drill) {
    final m = RegExp(r'^drill#(\d+)@(\w+)$').firstMatch(s.id);
    if (m == null) return null;
    final i = int.parse(m.group(1)!);
    if (i >= drill.vocab.length) return null;
    return (drill.vocab[i], DrillMode.parse(m.group(2)));
  }

  DrillMode _pickMode(Lexeme l, Random rnd, int i) {
    // Recognition first, production later in the round.
    final early = [DrillMode.meaning, DrillMode.listen, DrillMode.article, DrillMode.reverse];
    final late = [DrillMode.spell, DrillMode.context, DrillMode.plural, DrillMode.reverse, DrillMode.conjugate, DrillMode.perfekt];
    final pool = (i < 4 ? early : late).where((m) => supports(l, m)).toList();
    if (pool.isEmpty) return DrillMode.meaning;
    return pool[rnd.nextInt(pool.length)];
  }

  LessonStep? _step(Lexeme l, DrillMode mode, Random rnd, String baseId) {
    final id = '$baseId@${mode.name}';
    final example = l.examples.isEmpty ? null : l.examples.first;
    final explain = [
      '${l.headword} = ${l.tr}',
      if (example != null) '${example.de}\n${example.tr}',
    ].join('\n\n');
    switch (mode) {
      case DrillMode.meaning:
        final opts = _options(l.tr, _distractors(l, rnd).map((d) => d.tr), rnd);
        return ChoiceStep(id, promptTr: 'Bu kelimenin anlamı ne?', de: l.headword, options: opts.$1, answers: [opts.$2], explainTr: explain);
      case DrillMode.reverse:
        final opts = _options(l.headword, _distractors(l, rnd).map((d) => d.headword), rnd);
        return ChoiceStep(id, promptTr: '"${l.tr}" Almancada hangisi?', options: opts.$1, answers: [opts.$2], explainTr: explain);
      case DrillMode.listen:
        final opts = _options(l.tr, _distractors(l, rnd).map((d) => d.tr), rnd);
        return ListenStep(id, de: l.headword, promptTr: 'Ne duydun? Anlamını seç.', options: opts.$1, answers: [opts.$2], explainTr: explain);
      case DrillMode.article:
        return ArticleStep(id, lexemeId: l.id);
      case DrillMode.plural:
        final wrong = pluralDistractors(l);
        if (wrong.length < 2) return _step(l, DrillMode.meaning, rnd, baseId);
        final opts = _options(l.plural!, wrong.take(3), rnd);
        return ChoiceStep(
          id,
          promptTr: 'Çoğulu hangisi?',
          de: l.headword,
          options: opts.$1,
          answers: [opts.$2],
          explainTr: [
            '${l.headword} → ${l.plural}',
            'Çoğulda artikel her zaman "die" olur. Çoğul eki kelimeyle birlikte öğrenilmeli.',
            ?l.noteTr,
          ].join('\n\n'),
        );
      case DrillMode.spell:
        return TranslateStep(
          id,
          tr: '${l.tr}  (${l.pos.labelTr})',
          answers: [l.headword],
          hintTr: l.isNoun ? 'Artikeliyle yaz: ${l.article} …' : 'İlk harf: ${l.lemma.substring(0, 1)}',
          explainTr: example == null ? null : '${example.de}\n${example.tr}',
        );
      case DrillMode.context:
        final c = contextFor(l);
        if (c == null) return _step(l, DrillMode.meaning, rnd, baseId);
        return ClozeStep(
          id,
          de: c.$1,
          tr: '${c.$3}\nKelime: ${l.lemma} (${l.tr})',
          answers: [c.$2],
          explainTr: c.$1.replaceFirst('___', c.$2),
        );
      case DrillMode.conjugate:
        final forms = l.verb!.presentForms;
        final keys = forms.keys.toList()..sort();
        final key = keys[rnd.nextInt(keys.length)];
        final pronoun = _pronoun(key);
        return ClozeStep(
          id,
          de: '${pronoun[0].toUpperCase()}${pronoun.substring(1)} ___ …',
          tr: '${l.lemma} (${l.tr}) · ${_pronounTr(key)}',
          answers: [forms[key]!],
          explainTr: [
            for (final k in keys) '${_pronoun(k)} ${forms[k]}',
          ].join(' · '),
        );
      case DrillMode.perfekt:
        final v = l.verb!;
        final aux = v.auxiliaryShort;
        final other = aux == 'ist' ? 'hat' : 'ist';
        final stem = l.lemma.endsWith('en') ? l.lemma.substring(0, l.lemma.length - 2) : l.lemma.substring(0, l.lemma.length - 1);
        final correct = '$aux ${v.participle}';
        final wrong = <String>{
          '$other ${v.participle}',
          if ('ge${stem}t' != v.participle) '$aux ge${stem}t',
          if ('ge${stem}en' != v.participle) '$aux ge${stem}en',
          '$aux ${l.lemma}',
        }..remove(correct);
        final opts = _options(correct, wrong.take(3), rnd);
        return ChoiceStep(
          id,
          promptTr: '"${l.lemma}" (${l.tr}) – Perfekt: er/sie …',
          options: opts.$1,
          answers: [opts.$2],
          explainTr: [
            'er/sie $correct',
            v.auxiliary == 'sein'
                ? 'Yer değiştirme ya da durum değişikliği bildiren fiiller "sein" alır.'
                : 'Fiillerin çoğu Perfekt\'te "haben" alır.',
          ].join('\n\n'),
        );
      case DrillMode.match || DrillMode.mixed:
        return null;
    }
  }

  static String _pronoun(String key) => switch (key) {
        'er/sie/es' => 'er',
        'sie/Sie' => 'sie',
        _ => key,
      };

  static String _pronounTr(String key) => switch (key) {
        'ich' => 'ich (ben)',
        'du' => 'du (sen)',
        'er/sie/es' => 'er (o, erkek)',
        'wir' => 'wir (biz)',
        'ihr' => 'ihr (siz, samimi)',
        _ => 'sie (onlar)',
      };

  MatchStep? _match(List<Lexeme> words, String id) {
    final seenTr = <String>{};
    final seenDe = <String>{};
    final pairs = <MatchPair>[];
    for (final w in words) {
      if (seenTr.add(w.tr) && seenDe.add(w.headword)) pairs.add(MatchPair(de: w.headword, tr: w.tr));
    }
    if (pairs.length < 3) return null;
    return MatchStep(id, pairs: pairs, promptTr: 'Kelimeleri anlamlarıyla eşleştir');
  }

  /// Three other words, preferably of the same part of speech and level,
  /// whose meaning and headword differ from [l].
  List<Lexeme> _distractors(Lexeme l, Random rnd) {
    final pool = lexicon.all
        .where((x) => x.id != l.id && _usable(x) && x.tr != l.tr && x.headword != l.headword && !_overlap(x.tr, l.tr))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    pool.shuffle(rnd);
    final same = pool.where((x) => x.pos == l.pos);
    final picked = <Lexeme>[...same.take(3)];
    for (final x in pool) {
      if (picked.length >= 3) break;
      if (!picked.contains(x)) picked.add(x);
    }
    return picked;
  }

  /// Meanings that share a word ("ev" / "ev arkadaşı") would make a
  /// confusing choice, so such words are not used as distractors.
  static bool _overlap(String a, String b) {
    Set<String> parts(String s) => s.toLowerCase().split(RegExp(r'[\s,;/()]+')).where((w) => w.length > 2).toSet();
    return parts(a).intersection(parts(b)).isNotEmpty;
  }

  (List<String>, int) _options(String answer, Iterable<String> wrong, Random rnd) {
    final opts = <String>{answer, ...wrong}.toList()..shuffle(rnd);
    return (opts, opts.indexOf(answer));
  }

  /// Plausible but wrong plurals made with the common plural endings.
  /// Nouns known to have more than one accepted plural are skipped.
  static const _variablePlural = {'pizza', 'kaffee', 'tee', 'saft', 'konto', 'thema', 'museum', 'kaktus', 'virus', 'globus', 'ticket', 'joghurt'};

  static List<String> pluralDistractors(Lexeme l) {
    if (!hasPlural(l) || _variablePlural.contains(l.id)) return const [];
    final lemma = l.lemma;
    final umlaut = _umlaut(lemma);
    final endsE = lemma.endsWith('e');
    final candidates = <String>[
      'die $lemma',
      if (!endsE) 'die ${lemma}e',
      endsE ? 'die ${lemma}n' : 'die ${lemma}en',
      'die ${lemma}s',
      if (!endsE) 'die ${lemma}er',
      if (umlaut != null) 'die ${umlaut}e',
      if (umlaut != null && !lemma.endsWith('er')) 'die ${umlaut}er',
      if (umlaut != null && lemma.endsWith('er')) 'die $umlaut',
    ];
    final correct = l.plural!;
    return {for (final c in candidates) if (c != correct) c}.toList();
  }

  /// Umlauts the last a/o/u/au of [s], or null if it has none.
  static String? _umlaut(String s) {
    final m = RegExp(r'(au|a|o|u)(?=[^aeiouäöü]*(e[rln]?)?$)').allMatches(s).lastOrNull;
    if (m == null) return null;
    final rep = const {'au': 'äu', 'a': 'ä', 'o': 'ö', 'u': 'ü'}[m.group(1)]!;
    return s.replaceRange(m.start, m.end, rep);
  }

  /// An example sentence of [l] with one form of it blanked out:
  /// (sentence with ___, the missing form, Turkish translation).
  (String, String, String)? contextFor(Lexeme l) {
    if (l.isMultiWord || l.pos == PartOfSpeech.number) return null;
    final forms = <String>{
      l.lemma,
      ...l.forms.where((f) => !f.contains(' ')),
      if (l.verb != null) ...[l.verb!.present3, l.verb!.participle, ...l.verb!.presentForms.values],
    }.map((f) => f.toLowerCase()).toSet();
    for (final e in l.examples) {
      for (final m in RegExp(r'[\p{L}]+', unicode: true).allMatches(e.de)) {
        final w = m.group(0)!;
        if (forms.contains(w.toLowerCase())) {
          return (e.de.replaceRange(m.start, m.end, '___'), w, e.tr);
        }
      }
    }
    return null;
  }
}

/// Level order for choosing content; unknown levels sort last.
int levelRank(String level) => const {'A0': 0, 'A1': 1, 'A2': 2, 'B1': 3, 'B2': 4}[level] ?? 9;

/// Today's new words: not saved yet, at or below the learner's level,
/// preferably matching their interests. Deterministic for a given day so
/// the card does not change on every refresh.
List<Lexeme> pickDailyWords(
  Lexicon lexicon, {
  required Set<String> saved,
  required Set<String> interests,
  required String level,
  required DateTime day,
  int count = 5,
}) {
  final maxLevel = levelRank(level);
  final pool = lexicon.all
      .where((l) =>
          !saved.contains(l.id) &&
          !l.tags.contains('proper') &&
          levelRank(l.cefr) <= maxLevel &&
          l.pos != PartOfSpeech.number &&
          !l.isMultiWord)
      .toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  if (pool.isEmpty) return const [];
  final rnd = Random(day.year * 10000 + day.month * 100 + day.day);
  pool.shuffle(rnd);
  // Newest level first so a learner is not handed words far below their level,
  // then interests, keeping the shuffle order inside each group.
  int score(Lexeme l) => (levelRank(l.cefr) == maxLevel ? 2 : 0) + (l.tags.any(interests.contains) ? 3 : 0);
  final ranked = [...pool]..sort((a, b) => score(b).compareTo(score(a)));
  return ranked.take(count).toList(growable: false);
}
