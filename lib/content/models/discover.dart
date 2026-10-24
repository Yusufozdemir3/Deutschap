import '../json_utils.dart';

enum DiscoverKind {
  phrase,
  mistake,
  compare,
  culture,
  mystery,
  situation,
  miniStory;

  static DiscoverKind parse(String s) => switch (s) {
        'phrase' => phrase,
        'mistake' => mistake,
        'compare' => compare,
        'culture' => culture,
        'mystery' => mystery,
        'situation' => situation,
        'mini_story' => miniStory,
        _ => throw ContentFormatException('unknown discover kind "$s"'),
      };

  String get labelTr => switch (this) {
        phrase => 'Bugün kullanabileceğin ifade',
        mistake => 'Sık yapılan hata',
        compare => 'Benzer ifadeler',
        culture => 'Gündelik hayat',
        mystery => 'Mini gizem',
        situation => 'Sen ne derdin?',
        miniStory => '60 saniyelik hikâye',
      };
}

/// One self-contained, finite learning item for the "Entdecken" feed.
class DiscoverCard {
  const DiscoverCard({
    required this.id,
    required this.kind,
    required this.level,
    required this.minutes,
    required this.objectiveTr,
    required this.title,
    required this.bodyDe,
    required this.bodyTr,
    required this.explainTr,
    this.topics = const [],
    this.lexemes = const [],
    this.question,
    this.options = const [],
    this.answer,
  });

  final String id;
  final DiscoverKind kind;
  final String level;
  final int minutes;
  final String objectiveTr;
  final String title;
  final String bodyDe;
  final String bodyTr;

  /// Revealed after the learner predicts/answers (or taps "show").
  final String explainTr;
  final List<String> topics;
  final List<String> lexemes;

  /// Optional prediction question before the reveal.
  final String? question;
  final List<String> options;
  final int? answer;

  bool get hasQuestion => question != null && options.isNotEmpty && answer != null;

  factory DiscoverCard.fromJson(Json j) => DiscoverCard(
        id: j.str('id'),
        kind: DiscoverKind.parse(j.str('kind')),
        level: j.str('level'),
        minutes: j.integer('minutes', fallback: 1),
        objectiveTr: j.str('objective_tr'),
        title: j.str('title'),
        bodyDe: j.str('body_de'),
        bodyTr: j.str('body_tr'),
        explainTr: j.str('explain_tr'),
        topics: j.strList('topics'),
        lexemes: j.strList('lexemes'),
        question: j.optStr('question_tr'),
        options: j.strList('options'),
        answer: j['answer'] as int?,
      );
}
