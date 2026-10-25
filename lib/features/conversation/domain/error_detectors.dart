import '../../../learning/text/lexicon.dart';
import '../../../learning/text/tokenizer.dart';
import 'language_issue.dart';

/// Deterministic checks for frequent A1–A2 errors. Each detector only
/// fires on patterns it can judge reliably; anything else is left alone
/// rather than "corrected" wrongly. Coverage is intentionally narrow and
/// documented in docs/AI_DESIGN.md.
class ErrorDetectors {
  ErrorDetectors(this.lexicon);
  final Lexicon lexicon;

  List<LanguageIssue> check(String text, {bool formalContext = false, bool serviceContext = false}) {
    final issues = <LanguageIssue>[
      ..._perfektAuxiliary(text),
      ..._accusativeArticle(text),
      ..._inversion(text),
      if (formalContext) ..._register(text),
      if (serviceContext) ..._politeness(text),
      ..._nounCapitalisation(text),
    ];
    issues.sort((a, b) {
      final s = a.severity.index.compareTo(b.severity.index);
      return s != 0 ? s : a.kind.priority.compareTo(b.kind.priority);
    });
    return issues;
  }

  /// Replaces word number [index] in [text], keeping everything else.
  static String replaceWord(String text, int index, String replacement) {
    final t = tokenize(text);
    final b = StringBuffer();
    for (final tok in t) {
      b.write(tok.isWord && tok.wordIndex == index ? replacement : tok.text);
    }
    return b.toString();
  }

  static String _matchCase(String model, String word) =>
      model.isNotEmpty && model[0] == model[0].toUpperCase() ? word[0].toUpperCase() + word.substring(1) : word;

  // --- Perfekt with "sein" -------------------------------------------------

  static const _haben = {'habe': 'bin', 'hast': 'bist', 'hat': 'ist', 'haben': 'sind', 'habt': 'seid'};

  /// Participles that take "sein" in their common intransitive use.
  static const _seinParticiples = {
    'gegangen',
    'gekommen',
    'gelaufen',
    'geblieben',
    'gewesen',
    'geworden',
    'angekommen',
    'aufgestanden',
    'eingeschlafen',
    'passiert',
    'gestorben',
    'gereist',
    'mitgekommen',
    'zurückgekommen',
  };

  /// Usually "sein", but "haben" is correct with a direct object
  /// ("Ich habe das Auto gefahren"), so the message is hedged.
  static const _motionParticiples = {'gefahren', 'geflogen'};

  Iterable<LanguageIssue> _perfektAuxiliary(String text) sync* {
    final w = words(text);
    final lower = w.map((x) => x.toLowerCase()).toList();
    // Auxiliary and participle must be in the same sentence.
    final sentenceEnd = <int>[];
    var count = 0;
    for (final m in RegExp(r'[^.!?;]+[.!?;]*').allMatches(text)) {
      count += words(m.group(0)!).length;
      sentenceEnd.add(count);
    }
    int endOf(int i) => sentenceEnd.firstWhere((e) => e > i, orElse: () => lower.length);
    for (var i = 0; i < lower.length; i++) {
      final sein = _haben[lower[i]];
      if (sein == null) continue;
      for (var k = i + 1; k < endOf(i) && k < lower.length; k++) {
        final p = lower[k];
        final definite = _seinParticiples.contains(p);
        final motion = _motionParticiples.contains(p);
        if (!definite && !motion) continue;
        if (motion && _hasLikelyObject(lower.sublist(i + 1, k))) break;
        final corrected = replaceWord(text, i, _matchCase(w[i], sein));
        yield LanguageIssue(
          kind: IssueKind.grammar,
          severity: IssueSeverity.error,
          original: text,
          corrected: corrected,
          ruleId: 'perfekt_sein',
          explanationTr: definite
              ? '"${w[k]}" Perfekt\'te "sein" ile kurulur: yer değiştirme (gehen, kommen…) veya durum değişikliği (werden, einschlafen…) bildiren fiiller "sein" alır. "${w[i]}" yerine "$sein".'
              : 'Bir yere gitmeyi anlatıyorsan "${w[k]}" Perfekt\'te "sein" alır: "$sein … ${w[k]}". (Bir şeyi sürmek/uçurmak anlamında, nesneyle, "haben" doğrudur.)',
        );
        return;
      }
    }
  }

  static const _objectWords = {'den', 'das', 'ihn', 'es', 'mein', 'meinen', 'dein', 'deinen', 'sein', 'seinen', 'ihr', 'ihren', 'mich', 'dich', 'uns', 'euch'};
  static bool _hasLikelyObject(List<String> between) => between.any(_objectWords.contains);

  // --- Accusative article after common transitive verbs --------------------

  static const _accusativeTriggers = {
    'möchte', 'möchtest', 'möchten', 'nehme', 'nimmst', 'nehmen', 'brauche', 'brauchst', 'brauchen',
    'kaufe', 'kaufst', 'kaufen', 'bestelle', 'bestellen', 'habe', 'hast', 'haben', 'suche', 'suchst', 'suchen',
    'hätte', 'hätten', 'sehe', 'siehst', 'sehen', 'trinke', 'trinkst', 'trinken', 'esse', 'isst', 'essen',
  };
  static const _fillers = {'gern', 'gerne', 'bitte', 'noch', 'auch', 'lieber', 'heute', 'jetzt', 'dann', 'also'};
  static const _articleType = {
    'ein': 'indef', 'einen': 'indef', 'eine': 'indef',
    'kein': 'neg', 'keinen': 'neg', 'keine': 'neg',
    'der': 'def', 'den': 'def', 'die': 'def', 'das': 'def',
  };
  static const _accusative = {
    'indef': {'der': 'einen', 'die': 'eine', 'das': 'ein'},
    'neg': {'der': 'keinen', 'die': 'keine', 'das': 'kein'},
    'def': {'der': 'den', 'die': 'die', 'das': 'das'},
  };

  Iterable<LanguageIssue> _accusativeArticle(String text) sync* {
    final w = words(text);
    final lower = w.map((x) => x.toLowerCase()).toList();
    for (var i = 0; i < lower.length; i++) {
      if (!_accusativeTriggers.contains(lower[i])) continue;
      // Infinitive at the end ("Ich möchte … essen") is not a trigger position.
      if (i == lower.length - 1) continue;
      var j = i + 1;
      while (j < lower.length && (_fillers.contains(lower[j]) || _isPronounSubject(lower[j]))) {
        j++;
      }
      if (j + 1 >= lower.length) continue;
      final type = _articleType[lower[j]];
      if (type == null) continue;
      final noun = lexicon.nounForm(w[j + 1]);
      if (noun == null || noun.article == null) continue;
      if (noun.lemma.toLowerCase() != lower[j + 1]) continue; // only singular lemma
      final pluralSame = noun.plural?.split(' ').last.toLowerCase() == noun.lemma.toLowerCase();
      if (pluralSame && (lower[j] == 'die' || lower[j] == 'keine')) continue;
      final expected = _accusative[type]![noun.article!]!;
      if (expected == lower[j]) continue;
      final corrected = replaceWord(text, j, _matchCase(w[j], expected));
      yield LanguageIssue(
        kind: IssueKind.grammar,
        severity: IssueSeverity.error,
        original: text,
        corrected: corrected,
        ruleId: 'akkusativ_${noun.article}',
        explanationTr: noun.article == 'der'
            ? '"${noun.headword}" eril (der). "${w[i]}" fiilinin nesnesi Akkusativ olur ve eril tanımlıklar değişir: der → den, ein → einen, kein → keinen. Doğrusu: "$expected ${noun.lemma}".'
            : '"${noun.headword}" ${noun.article == 'die' ? 'dişil (die)' : 'nötr (das)'}. Akkusativ\'de sadece eril tanımlıklar değişir, bu yüzden doğrusu: "$expected ${noun.lemma}".',
      );
      return;
    }
  }

  static bool _isPronounSubject(String w) => const {'ich', 'du', 'wir', 'sie', 'er', 'ihr'}.contains(w);

  // --- Verb-second after a fronted time adverb -----------------------------

  static const _frontAdverbs = {'heute', 'morgen', 'gestern', 'dann', 'danach', 'jetzt', 'später', 'abends', 'morgens', 'manchmal', 'oft', 'hier', 'dort'};
  static const _subjects = {'ich', 'du', 'er', 'sie', 'es', 'wir', 'ihr'};

  Iterable<LanguageIssue> _inversion(String text) sync* {
    final w = words(text);
    if (w.length < 3) return;
    final a = w[0].toLowerCase();
    final b = w[1].toLowerCase();
    if (!_frontAdverbs.contains(a) || !_subjects.contains(b)) return;
    // The third word must look like a finite verb, not e.g. "Heute ich und du…".
    final third = w[2].toLowerCase();
    if (const {'und', 'oder', 'aber'}.contains(third)) return;
    var corrected = replaceWord(text, 1, w[2]);
    corrected = replaceWord(corrected, 2, b);
    yield LanguageIssue(
      kind: IssueKind.wordOrder,
      severity: IssueSeverity.error,
      original: text,
      corrected: corrected,
      ruleId: 'verb_zweit',
      explanationTr: 'Almanca ana cümlede çekimli fiil 2. sıradadır. Cümle "${w[0]}" ile başlıyorsa önce fiil, sonra özne gelir: "${w[0]} ${w[2]} $b …".',
    );
  }

  // --- du/Sie register --------------------------------------------------------

  Iterable<LanguageIssue> _register(String text) sync* {
    final lower = words(text).map((x) => x.toLowerCase()).toSet();
    if (lower.intersection(const {'du', 'dich', 'dir', 'dein', 'deine', 'deinen', 'hast', 'kannst', 'bist'}).isEmpty) return;
    yield LanguageIssue(
      kind: IssueKind.register,
      severity: IssueSeverity.suggestion,
      original: text,
      corrected: text,
      ruleId: 'register_sie',
      explanationTr: 'Anlaşıldı. Ama tanımadığın birine, hizmet ortamında "Sie" ile hitap etmek daha uygun: "Haben Sie …?", "Können Sie …?".',
    );
  }

  // --- Polite requests ------------------------------------------------------

  Iterable<LanguageIssue> _politeness(String text) sync* {
    final w = words(text);
    for (var i = 0; i + 1 < w.length; i++) {
      if (w[i].toLowerCase() == 'ich' && w[i + 1].toLowerCase() == 'will') {
        yield LanguageIssue(
          kind: IssueKind.style,
          severity: IssueSeverity.suggestion,
          original: text,
          corrected: replaceWord(text, i + 1, 'möchte'),
          ruleId: 'polite_moechte',
          explanationTr: '"Ich will …" dil bilgisi olarak doğru ama sipariş verirken sert duyulur ("istiyorum!" gibi). "Ich möchte …" veya "Ich hätte gern …" daha kibar.',
        );
        return;
      }
    }
  }

  // --- Noun capitalisation --------------------------------------------------

  Iterable<LanguageIssue> _nounCapitalisation(String text) sync* {
    final t = tokenize(text).where((x) => x.isWord).toList();
    for (final tok in t) {
      final s = tok.text;
      if (s.isEmpty || s[0] != s[0].toLowerCase() || s[0] == s[0].toUpperCase()) continue;
      final hits = lexicon.lookupWord(s);
      if (hits.confidence != LookupConfidence.exact || hits.isEmpty) continue;
      if (!hits.lexemes.every((l) => l.isNoun)) continue; // "essen" vs "Essen"
      if (hits.lexemes.any((l) => l.forms.contains(s))) continue; // listed lower-case form: "montags"
      final fixed = s[0].toUpperCase() + s.substring(1);
      yield LanguageIssue(
        kind: IssueKind.spelling,
        severity: IssueSeverity.error,
        original: text,
        corrected: replaceWord(text, tok.wordIndex, fixed),
        ruleId: 'noun_caps',
        explanationTr: 'Almancada bütün isimler büyük harfle başlar: "$fixed".',
      );
      return;
    }
  }
}
