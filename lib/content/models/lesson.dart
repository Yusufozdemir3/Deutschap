import '../json_utils.dart';

class LearningPath {
  const LearningPath({required this.level, required this.units});
  final String level;
  final List<Unit> units;

  factory LearningPath.fromJson(Json j) => LearningPath(
        level: j.str('level'),
        units: j.objList('units').map(Unit.fromJson).toList(growable: false),
      );
}

class Unit {
  const Unit({
    required this.id,
    required this.number,
    required this.titleDe,
    required this.titleTr,
    required this.goalTr,
    required this.lessons,
    this.grammar = const [],
  });

  final String id;
  final int number;
  final String titleDe;
  final String titleTr;
  final String goalTr;
  final List<String> grammar;
  final List<Lesson> lessons;

  /// Units listed in the curriculum whose lessons are not written yet.
  bool get isPlanned => lessons.isEmpty;

  factory Unit.fromJson(Json j) => Unit(
        id: j.str('id'),
        number: j.integer('number'),
        titleDe: j.str('title_de'),
        titleTr: j.str('title_tr'),
        goalTr: j.str('goal_tr'),
        grammar: j.strList('grammar'),
        lessons: j.objList('lessons').map(Lesson.fromJson).toList(growable: false),
      );
}

class Lesson {
  const Lesson({
    required this.id,
    required this.titleTr,
    required this.objectiveTr,
    required this.minutes,
    required this.steps,
    this.vocab = const [],
  });

  final String id;
  final String titleTr;
  final String objectiveTr;
  final int minutes;
  final List<String> vocab;
  final List<LessonStep> steps;

  int get gradedStepCount => steps.where((s) => s.isGraded).length;

  factory Lesson.fromJson(Json j) {
    final id = j.str('id');
    final steps = <LessonStep>[];
    final raw = j.objList('steps');
    for (var i = 0; i < raw.length; i++) {
      try {
        steps.add(LessonStep.fromJson(raw[i], '$id#$i'));
      } on ContentFormatException catch (e) {
        throw ContentFormatException('lesson $id step $i: ${e.message}');
      }
    }
    return Lesson(
      id: id,
      titleTr: j.str('title_tr'),
      objectiveTr: j.str('objective_tr'),
      minutes: j.integer('minutes', fallback: 5),
      vocab: j.strList('vocab'),
      steps: steps,
    );
  }
}

sealed class LessonStep {
  const LessonStep(this.id);

  /// Stable id: `lessonId#index` unless the content sets one.
  final String id;

  bool get isGraded => true;

  factory LessonStep.fromJson(Json j, String fallbackId) {
    final id = j.optStr('id') ?? fallbackId;
    return switch (j.str('type')) {
      'intro' => IntroStep(id, lexemes: j.strList('lexemes'), noteTr: j.optStr('note_tr')),
      'grammar' => GrammarStep(id, conceptId: j.str('concept')),
      'dialogue' => DialogueStep(
          id,
          titleTr: j.optStr('title_tr'),
          lines: j.objList('lines').map(DialogueLine.fromJson).toList(growable: false),
        ),
      'choice' => ChoiceStep(
          id,
          promptTr: j.str('prompt_tr'),
          de: j.optStr('de'),
          options: j.strList('options'),
          answers: j.intList('answers'),
          explainTr: j.str('explain_tr'),
        ),
      'article' => ArticleStep(id, lexemeId: j.str('lexeme')),
      'cloze' => ClozeStep(
          id,
          de: j.str('de'),
          tr: j.str('tr'),
          answers: j.strList('answers'),
          options: j.strList('options'),
          explainTr: j.str('explain_tr'),
        ),
      'order' => OrderStep(
          id,
          tr: j.str('tr'),
          tokens: j.strList('tokens'),
          answers: j.strList('answers'),
          explainTr: j.optStr('explain_tr'),
        ),
      'translate' => TranslateStep(
          id,
          tr: j.str('tr'),
          answers: j.strList('answers'),
          hintTr: j.optStr('hint_tr'),
          explainTr: j.optStr('explain_tr'),
        ),
      'listen' => ListenStep(
          id,
          de: j.str('de'),
          promptTr: j.str('prompt_tr'),
          options: j.strList('options'),
          answers: j.intList('answers'),
          explainTr: j.str('explain_tr'),
        ),
      'write' => WriteStep(
          id,
          promptTr: j.str('prompt_tr'),
          requirements: j.objList('requirements').map(WriteRequirement.fromJson).toList(growable: false),
          model: j.str('model'),
          minWords: j.integer('min_words', fallback: 3),
        ),
      final t => throw ContentFormatException('unknown step type "$t"'),
    };
  }
}

/// Presents new vocabulary (with audio and "save").
class IntroStep extends LessonStep {
  const IntroStep(super.id, {required this.lexemes, this.noteTr});
  final List<String> lexemes;
  final String? noteTr;
  @override
  bool get isGraded => false;
}

class GrammarStep extends LessonStep {
  const GrammarStep(super.id, {required this.conceptId});
  final String conceptId;
  @override
  bool get isGraded => false;
}

class DialogueLine {
  const DialogueLine({required this.speaker, required this.de, required this.tr});
  final String speaker;
  final String de;
  final String tr;
  factory DialogueLine.fromJson(Json j) =>
      DialogueLine(speaker: j.str('speaker'), de: j.str('de'), tr: j.str('tr'));
}

class DialogueStep extends LessonStep {
  const DialogueStep(super.id, {required this.lines, this.titleTr});
  final String? titleTr;
  final List<DialogueLine> lines;
  @override
  bool get isGraded => false;
}

/// Multiple choice; [answers] lists every acceptable option index.
class ChoiceStep extends LessonStep {
  const ChoiceStep(
    super.id, {
    required this.promptTr,
    required this.options,
    required this.answers,
    required this.explainTr,
    this.de,
  });
  final String promptTr;
  final String? de;
  final List<String> options;
  final List<int> answers;
  final String explainTr;
}

class ArticleStep extends LessonStep {
  const ArticleStep(super.id, {required this.lexemeId});
  final String lexemeId;
}

/// Sentence with one "___" gap. With [options] it is a choice, otherwise typed.
class ClozeStep extends LessonStep {
  const ClozeStep(
    super.id, {
    required this.de,
    required this.tr,
    required this.answers,
    required this.explainTr,
    this.options = const [],
  });
  final String de;
  final String tr;
  final List<String> answers;
  final List<String> options;
  final String explainTr;
}

/// Build a sentence from shuffled tokens. Several orders may be valid.
class OrderStep extends LessonStep {
  const OrderStep(super.id, {required this.tr, required this.tokens, required this.answers, this.explainTr});
  final String tr;
  final List<String> tokens;
  final List<String> answers;
  final String? explainTr;
}

/// Free typed translation from Turkish; every listed answer is accepted.
class TranslateStep extends LessonStep {
  const TranslateStep(super.id, {required this.tr, required this.answers, this.hintTr, this.explainTr});
  final String tr;
  final List<String> answers;
  final String? hintTr;
  final String? explainTr;
}

/// Listening comprehension. The text can be revealed (counts as help),
/// and is shown automatically when no German voice is available.
class ListenStep extends LessonStep {
  const ListenStep(
    super.id, {
    required this.de,
    required this.promptTr,
    required this.options,
    required this.answers,
    required this.explainTr,
  });
  final String de;
  final String promptTr;
  final List<String> options;
  final List<int> answers;
  final String explainTr;
}

class WriteRequirement {
  const WriteRequirement({required this.labelTr, required this.pattern});
  final String labelTr;

  /// Regular expression over the folded answer (lower case, ä→ae …).
  final String pattern;

  factory WriteRequirement.fromJson(Json j) => WriteRequirement(labelTr: j.str('label_tr'), pattern: j.str('pattern'));
}

/// Short free writing. Checked for task completion (requirements) and
/// with the deterministic error detectors; a model answer is shown, and
/// the learner is told the automatic check is limited.
class WriteStep extends LessonStep {
  const WriteStep(super.id, {required this.promptTr, required this.requirements, required this.model, this.minWords = 3});
  final String promptTr;
  final List<WriteRequirement> requirements;
  final String model;
  final int minWords;
}
