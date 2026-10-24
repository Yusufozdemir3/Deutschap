import '../json_utils.dart';

class Story {
  const Story({
    required this.id,
    required this.title,
    required this.subtitleTr,
    required this.premiseTr,
    required this.characters,
    required this.episodes,
  });

  final String id;
  final String title;
  final String subtitleTr;
  final String premiseTr;
  final List<StoryCharacter> characters;

  /// All episodes of all language variants. An episode is identified by
  /// [Episode.number]; several levels of the same number are variants.
  final List<Episode> episodes;

  StoryCharacter? character(String id) {
    for (final c in characters) {
      if (c.id == id) return c;
    }
    return null;
  }

  List<int> get episodeNumbers => {for (final e in episodes) e.number}.toList()..sort();

  /// Best variant for a learner level: the highest level not above it,
  /// otherwise the easiest available.
  Episode variantFor(int number, String learnerLevel) {
    final candidates = episodes.where((e) => e.number == number).toList()
      ..sort((a, b) => a.level.compareTo(b.level));
    Episode? best;
    for (final e in candidates) {
      if (e.level.compareTo(learnerLevel) <= 0) best = e;
    }
    return best ?? candidates.first;
  }

  factory Story.fromJson(Json j) => Story(
        id: j.str('id'),
        title: j.str('title'),
        subtitleTr: j.str('subtitle_tr'),
        premiseTr: j.str('premise_tr'),
        characters: j.objList('characters').map(StoryCharacter.fromJson).toList(growable: false),
        episodes: j.objList('episodes').map(Episode.fromJson).toList(growable: false),
      );
}

class StoryCharacter {
  const StoryCharacter({required this.id, required this.name, required this.roleTr, this.formal = false});
  final String id;
  final String name;
  final String roleTr;

  /// Whether the learner should address this character with "Sie".
  final bool formal;

  factory StoryCharacter.fromJson(Json j) => StoryCharacter(
        id: j.str('id'),
        name: j.str('name'),
        roleTr: j.str('role_tr'),
        formal: j.flag('formal'),
      );
}

class Episode {
  const Episode({
    required this.id,
    required this.number,
    required this.level,
    required this.title,
    required this.titleTr,
    required this.narrativeObjectiveTr,
    required this.learningObjectiveTr,
    required this.minutes,
    required this.start,
    required this.nodes,
    required this.recapTr,
    this.vocab = const [],
    this.grammar = const [],
    this.quiz = const [],
    this.teaserTr,
    this.scenarioId,
  });

  final String id;
  final int number;
  final String level;
  final String title;
  final String titleTr;
  final String narrativeObjectiveTr;
  final String learningObjectiveTr;
  final int minutes;
  final String start;
  final Map<String, StoryNode> nodes;
  final String recapTr;

  /// Key lexeme ids of the episode, shown in the recap.
  final List<String> vocab;
  final List<GrammarInsight> grammar;
  final List<QuizQuestion> quiz;
  final String? teaserTr;

  /// Practical scenario that rehearses this episode's language.
  final String? scenarioId;

  factory Episode.fromJson(Json j) {
    final id = j.str('id');
    try {
      final nodes = <String, StoryNode>{};
      for (final n in j.objList('nodes')) {
        final node = StoryNode.fromJson(n);
        if (nodes.containsKey(node.id)) {
          throw ContentFormatException('duplicate node ${node.id}');
        }
        nodes[node.id] = node;
      }
      return Episode(
        id: id,
        number: j.integer('number'),
        level: j.str('level'),
        title: j.str('title'),
        titleTr: j.str('title_tr'),
        narrativeObjectiveTr: j.str('narrative_tr'),
        learningObjectiveTr: j.str('objective_tr'),
        minutes: j.integer('minutes', fallback: 6),
        start: j.str('start'),
        nodes: nodes,
        recapTr: j.str('recap_tr'),
        vocab: j.strList('vocab'),
        grammar: j.objList('grammar').map(GrammarInsight.fromJson).toList(growable: false),
        quiz: j.objList('quiz').map(QuizQuestion.fromJson).toList(growable: false),
        teaserTr: j.optStr('teaser_tr'),
        scenarioId: j.optStr('scenario'),
      );
    } on ContentFormatException catch (e) {
      throw ContentFormatException('episode $id: ${e.message}');
    }
  }
}

sealed class StoryNode {
  const StoryNode(this.id);
  final String id;

  factory StoryNode.fromJson(Json j) {
    final id = j.str('id');
    return switch (j.str('type')) {
      'narration' => NarrationNode(id, de: j.str('de'), tr: j.str('tr'), next: j.str('next')),
      'line' => LineNode(
          id,
          speaker: j.str('speaker'),
          de: j.str('de'),
          tr: j.str('tr'),
          next: j.str('next'),
          glossTr: j.optStr('gloss_tr'),
        ),
      'choice' => ChoiceNode(
          id,
          promptTr: j.str('prompt_tr'),
          choices: j.objList('choices').map(StoryChoice.fromJson).toList(growable: false),
        ),
      'branch' => BranchNode(
          id,
          cases: j.objList('cases').map((c) => BranchCase(flag: c.str('flag'), next: c.str('next'))).toList(growable: false),
          otherwise: j.str('else'),
        ),
      'end' => EndNode(id),
      final t => throw ContentFormatException('node $id has unknown type "$t"'),
    };
  }
}

/// Narrator text (second person: the learner is the protagonist).
class NarrationNode extends StoryNode {
  const NarrationNode(super.id, {required this.de, required this.tr, required this.next});
  final String de;
  final String tr;
  final String next;
}

class LineNode extends StoryNode {
  const LineNode(super.id, {required this.speaker, required this.de, required this.tr, required this.next, this.glossTr});
  final String speaker;
  final String de;
  final String tr;
  final String next;

  /// Short explanation of the sentence's structure, written by the author.
  final String? glossTr;
}

class ChoiceNode extends StoryNode {
  const ChoiceNode(super.id, {required this.promptTr, required this.choices});
  final String promptTr;
  final List<StoryChoice> choices;
}

enum ChoiceVerdict { best, ok, wrong }

class StoryChoice {
  const StoryChoice({
    required this.id,
    required this.de,
    required this.tr,
    required this.verdict,
    required this.feedbackTr,
    this.next,
    this.setFlags = const [],
  });

  final String id;
  final String de;
  final String tr;
  final ChoiceVerdict verdict;
  final String feedbackTr;

  /// Where the story continues. Wrong choices usually have none: the
  /// learner sees the explanation and tries again.
  final String? next;
  final List<String> setFlags;

  factory StoryChoice.fromJson(Json j) => StoryChoice(
        id: j.str('id'),
        de: j.str('de'),
        tr: j.str('tr'),
        verdict: switch (j.str('verdict')) {
          'best' => ChoiceVerdict.best,
          'ok' => ChoiceVerdict.ok,
          'wrong' => ChoiceVerdict.wrong,
          final v => throw ContentFormatException('unknown verdict "$v"'),
        },
        feedbackTr: j.str('feedback_tr'),
        next: j.optStr('next'),
        setFlags: j.strList('flags'),
      );
}

class BranchCase {
  const BranchCase({required this.flag, required this.next});
  final String flag;
  final String next;
}

/// Invisible routing node: continues according to flags set by choices.
class BranchNode extends StoryNode {
  const BranchNode(super.id, {required this.cases, required this.otherwise});
  final List<BranchCase> cases;
  final String otherwise;
}

class EndNode extends StoryNode {
  const EndNode(super.id);
}

class GrammarInsight {
  const GrammarInsight({required this.titleTr, required this.bodyTr, required this.exampleDe, this.conceptId});
  final String titleTr;
  final String bodyTr;
  final String exampleDe;
  final String? conceptId;

  factory GrammarInsight.fromJson(Json j) => GrammarInsight(
        titleTr: j.str('title_tr'),
        bodyTr: j.str('body_tr'),
        exampleDe: j.str('example_de'),
        conceptId: j.optStr('concept'),
      );
}

class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.questionTr,
    required this.options,
    required this.answer,
    required this.explainTr,
  });
  final String id;
  final String questionTr;
  final List<String> options;
  final int answer;
  final String explainTr;

  factory QuizQuestion.fromJson(Json j) => QuizQuestion(
        id: j.str('id'),
        questionTr: j.str('question_tr'),
        options: j.strList('options'),
        answer: j.integer('answer'),
        explainTr: j.str('explain_tr'),
      );
}
