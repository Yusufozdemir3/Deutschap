import '../json_utils.dart';
import 'lexeme.dart';

/// A practical conversation with a defined objective and completion
/// condition (all [goals] reached). Matching is rule-based in v0.1; see
/// docs/AI_DESIGN.md for the planned AI-backed engine.
class Scenario {
  const Scenario({
    required this.id,
    required this.titleDe,
    required this.titleTr,
    required this.level,
    required this.objectiveTr,
    required this.settingTr,
    required this.partnerName,
    required this.partnerRoleTr,
    required this.formal,
    required this.service,
    required this.opening,
    required this.goals,
    required this.intents,
    required this.fallback,
    required this.closing,
    this.vocab = const [],
    this.disclaimerTr,
  });

  final String id;
  final String titleDe;
  final String titleTr;
  final String level;
  final String objectiveTr;
  final String settingTr;
  final String partnerName;
  final String partnerRoleTr;

  /// Whether "Sie" is expected. Using "du" triggers a register hint.
  final bool formal;

  /// Ordering/service situations, where "Ich will …" gets a politeness hint.
  final bool service;
  final Example opening;
  final List<ScenarioGoal> goals;
  final List<ScenarioIntent> intents;
  final List<Example> fallback;
  final Example closing;
  final List<String> vocab;

  /// Shown for administrative/medical topics: educational, not advice.
  final String? disclaimerTr;

  factory Scenario.fromJson(Json j) {
    final id = j.str('id');
    try {
      return Scenario(
        id: id,
        titleDe: j.str('title_de'),
        titleTr: j.str('title_tr'),
        level: j.str('level'),
        objectiveTr: j.str('objective_tr'),
        settingTr: j.str('setting_tr'),
        partnerName: j.str('partner'),
        partnerRoleTr: j.str('partner_role_tr'),
        formal: j.flag('formal', fallback: true),
        service: j.flag('service'),
        opening: Example.fromJson(j.optObj('opening')!),
        goals: j.objList('goals').map(ScenarioGoal.fromJson).toList(growable: false),
        intents: j.objList('intents').map(ScenarioIntent.fromJson).toList(growable: false),
        fallback: j.objList('fallback').map(Example.fromJson).toList(growable: false),
        closing: Example.fromJson(j.optObj('closing')!),
        vocab: j.strList('vocab'),
        disclaimerTr: j.optStr('disclaimer_tr'),
      );
    } on ContentFormatException catch (e) {
      throw ContentFormatException('scenario $id: ${e.message}');
    }
  }
}

class ScenarioGoal {
  const ScenarioGoal({required this.id, required this.labelTr, required this.hints});
  final String id;
  final String labelTr;

  /// Phrases offered in guided mode, from simplest to most natural.
  final List<Example> hints;

  factory ScenarioGoal.fromJson(Json j) => ScenarioGoal(
        id: j.str('id'),
        labelTr: j.str('label_tr'),
        hints: j.objList('hints').map(Example.fromJson).toList(growable: false),
      );
}

class ScenarioIntent {
  const ScenarioIntent({
    required this.id,
    required this.matches,
    this.goal,
    this.requires = const [],
    this.blocked,
  });

  final String id;

  /// Goal completed when this intent is recognised.
  final String? goal;

  /// Goals that must be done first; otherwise [blocked] is the reply.
  final List<String> requires;
  final Example? blocked;

  /// Ordered patterns; the first pattern that matches picks the reply.
  final List<IntentMatch> matches;

  factory ScenarioIntent.fromJson(Json j) {
    final b = j.optObj('blocked');
    return ScenarioIntent(
      id: j.str('id'),
      goal: j.optStr('goal'),
      requires: j.strList('requires'),
      blocked: b == null ? null : Example.fromJson(b),
      matches: j.objList('match').map(IntentMatch.fromJson).toList(growable: false),
    );
  }
}

class IntentMatch {
  const IntentMatch({required this.pattern, required this.reply});

  /// Regular expression applied to the folded learner text
  /// (lower case, ä→ae, ö→oe, ü→ue, ß→ss).
  final String pattern;
  final Example reply;

  factory IntentMatch.fromJson(Json j) => IntentMatch(
        pattern: j.str('pattern'),
        reply: Example(de: j.str('de'), tr: j.str('tr')),
      );
}
