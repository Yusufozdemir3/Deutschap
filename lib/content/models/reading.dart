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
  });

  final String id;
  final String title;
  final String level;
  final int minutes;
  final String topicTr;
  final List<ReadingParagraph> paragraphs;
  final List<ReadingQuestion> questions;

  String get body => paragraphs.map((p) => p.de).join('\n\n');

  factory ReadingText.fromJson(Json j) => ReadingText(
        id: j.str('id'),
        title: j.str('title'),
        level: j.str('level'),
        minutes: j.integer('minutes', fallback: 3),
        topicTr: j.str('topic_tr'),
        paragraphs: j.objList('paragraphs').map(ReadingParagraph.fromJson).toList(growable: false),
        questions: j.objList('questions').map(ReadingQuestion.fromJson).toList(growable: false),
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
