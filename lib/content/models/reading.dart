import '../json_utils.dart';

class ReadingText {
  const ReadingText({
    required this.id,
    required this.title,
    required this.level,
    required this.minutes,
    required this.topicTr,
    required this.paragraphs,
    this.questions = const [],
    this.sourceTr,
  });

  final String id;
  final String title;
  final String level;
  final int minutes;
  final String topicTr;
  final List<ReadingParagraph> paragraphs;
  final List<ReadingQuestion> questions;

  /// Where the text comes from and under which terms. Texts without a
  /// source were written for Deutschap.
  final String? sourceTr;

  String get body => paragraphs.map((p) => p.de).join('\n\n');

  factory ReadingText.fromJson(Json j) => ReadingText(
        id: j.str('id'),
        title: j.str('title'),
        level: j.str('level'),
        minutes: j.integer('minutes', fallback: 3),
        topicTr: j.str('topic_tr'),
        paragraphs: j.objList('paragraphs').map(ReadingParagraph.fromJson).toList(growable: false),
        questions: j.objList('questions').map(ReadingQuestion.fromJson).toList(growable: false),
        sourceTr: j.optStr('source_tr'),
      );
}

class ReadingParagraph {
  const ReadingParagraph({required this.de, required this.tr});
  final String de;
  final String tr;
  factory ReadingParagraph.fromJson(Json j) => ReadingParagraph(de: j.str('de'), tr: j.str('tr'));
}

class ReadingQuestion {
  const ReadingQuestion({required this.questionTr, required this.options, required this.answer, required this.explainTr});
  final String questionTr;
  final List<String> options;
  final int answer;
  final String explainTr;
  factory ReadingQuestion.fromJson(Json j) => ReadingQuestion(
        questionTr: j.str('question_tr'),
        options: j.strList('options'),
        answer: j.integer('answer'),
        explainTr: j.str('explain_tr'),
      );
}

/// A listening text: announcements, dialogues, voice messages, short
/// talks. Played line by line with device text-to-speech.
class ListeningTrack {
  const ListeningTrack({
    required this.id,
    required this.title,
    required this.level,
    required this.minutes,
    required this.topicTr,
    required this.kindTr,
    required this.lines,
    this.questions = const [],
    this.sourceTr,
  });

  final String id;
  final String title;
  final String level;
  final int minutes;
  final String topicTr;

  /// "Anons", "Diyalog", "Sesli mesaj" …
  final String kindTr;
  final List<ListeningLine> lines;
  final List<ReadingQuestion> questions;
  final String? sourceTr;

  /// Speakers in order of first appearance.
  List<String> get speakers => {for (final l in lines) l.speaker}.toList(growable: false);

  /// Lines short enough for dictation: 3–10 words, at most [max].
  List<int> dictationLines({int max = 3}) {
    final out = <int>[];
    for (var i = 0; i < lines.length && out.length < max; i++) {
      final n = lines[i].de.split(RegExp(r'\s+')).length;
      if (n >= 3 && n <= 10) out.add(i);
    }
    return out;
  }

  factory ListeningTrack.fromJson(Json j) => ListeningTrack(
        id: j.str('id'),
        title: j.str('title'),
        level: j.str('level'),
        minutes: j.integer('minutes', fallback: 2),
        topicTr: j.str('topic_tr'),
        kindTr: j.str('kind_tr'),
        lines: j.objList('lines').map(ListeningLine.fromJson).toList(growable: false),
        questions: j.objList('questions').map(ReadingQuestion.fromJson).toList(growable: false),
        sourceTr: j.optStr('source_tr'),
      );
}

class ListeningLine {
  const ListeningLine({required this.speaker, required this.de, required this.tr});
  final String speaker;
  final String de;
  final String tr;
  factory ListeningLine.fromJson(Json j) => ListeningLine(speaker: j.str('speaker'), de: j.str('de'), tr: j.str('tr'));
}
