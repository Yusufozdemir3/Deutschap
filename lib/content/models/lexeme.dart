import '../json_utils.dart';

enum PartOfSpeech {
  noun,
  verb,
  adjective,
  adverb,
  pronoun,
  preposition,
  conjunction,
  number,
  particle,
  expression;

  static PartOfSpeech parse(String s) => PartOfSpeech.values.firstWhere(
        (p) => p.name == s,
        orElse: () => throw ContentFormatException('unknown pos "$s"'),
      );

  String get labelTr => switch (this) {
        noun => 'isim',
        verb => 'fiil',
        adjective => 'sıfat',
        adverb => 'zarf',
        pronoun => 'zamir',
        preposition => 'edat',
        conjunction => 'bağlaç',
        number => 'sayı',
        particle => 'ünlem/edat',
        expression => 'kalıp ifade',
      };
}

enum Register { formal, neutral, informal }

class Example {
  const Example({required this.de, required this.tr});
  final String de;
  final String tr;

  factory Example.fromJson(Json j) => Example(de: j.str('de'), tr: j.str('tr'));
}

/// Verb information that learners need at A1–B1. Kept deliberately small
/// and explicit: nothing here is generated at runtime.
class VerbInfo {
  const VerbInfo({
    required this.present3,
    required this.auxiliary,
    required this.participle,
    this.separablePrefix,
    this.pattern,
    this.presentForms = const {},
  });

  /// er/sie/es form, e.g. "geht".
  final String present3;

  /// "haben" or "sein" for the Perfekt.
  final String auxiliary;
  final String participle;
  final String? separablePrefix;

  /// Typical pattern, e.g. "jemanden etwas fragen".
  final String? pattern;

  /// Optional full present tense: ich/du/er/wir/ihr/sie.
  final Map<String, String> presentForms;

  factory VerbInfo.fromJson(Json j) => VerbInfo(
        present3: j.str('present3'),
        auxiliary: j.str('aux'),
        participle: j.str('participle'),
        separablePrefix: j.optStr('separable'),
        pattern: j.optStr('pattern'),
        presentForms: (j.optObj('present') ?? const {}).map((k, v) => MapEntry(k, v as String)),
      );

  String get perfektExample => '$auxiliaryShort $participle';
  String get auxiliaryShort => auxiliary == 'sein' ? 'ist' : 'hat';
}

class Lexeme {
  const Lexeme({
    required this.id,
    required this.lemma,
    required this.pos,
    required this.tr,
    required this.cefr,
    this.article,
    this.plural,
    this.en,
    this.forms = const [],
    this.examples = const [],
    this.collocations = const [],
    this.related = const [],
    this.tags = const [],
    this.register = Register.neutral,
    this.verb,
    this.noteTr,
    this.commonMistakeTr,
  });

  final String id;

  /// Dictionary form without article ("Termin", "gehen", "einen Termin vereinbaren").
  final String lemma;
  final PartOfSpeech pos;

  /// "der" / "die" / "das" for nouns; null for plural-only or non-nouns.
  final String? article;

  /// Plural with article ("die Termine"); "—" means no plural in use.
  final String? plural;
  final String tr;
  final String? en;
  final String cefr;

  /// Surface forms that should resolve to this lexeme when tapped in a text.
  final List<String> forms;
  final List<Example> examples;
  final List<String> collocations;
  final List<String> related;
  final List<String> tags;
  final Register register;
  final VerbInfo? verb;
  final String? noteTr;
  final String? commonMistakeTr;

  bool get isNoun => pos == PartOfSpeech.noun;
  bool get isMultiWord => lemma.contains(' ');

  /// What a learner should memorise: nouns always with their article.
  String get headword => article != null ? '$article $lemma' : lemma;

  factory Lexeme.fromJson(Json j) {
    final id = j.str('id');
    try {
      final verb = j.optObj('verb');
      return Lexeme(
        id: id,
        lemma: j.str('lemma'),
        pos: PartOfSpeech.parse(j.str('pos')),
        article: j.optStr('article'),
        plural: j.optStr('plural'),
        tr: j.str('tr'),
        en: j.optStr('en'),
        cefr: j.optStr('cefr') ?? 'A1',
        forms: j.strList('forms'),
        examples: j.objList('examples').map(Example.fromJson).toList(growable: false),
        collocations: j.strList('collocations'),
        related: j.strList('related'),
        tags: j.strList('tags'),
        register: switch (j.optStr('register')) {
          'formal' => Register.formal,
          'informal' => Register.informal,
          _ => Register.neutral,
        },
        verb: verb == null ? null : VerbInfo.fromJson(verb),
        noteTr: j.optStr('note_tr'),
        commonMistakeTr: j.optStr('mistake_tr'),
      );
    } on ContentFormatException catch (e) {
      throw ContentFormatException('lexeme "$id": ${e.message}');
    }
  }
}
