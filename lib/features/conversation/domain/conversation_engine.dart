import '../../../content/models/scenario.dart';
import '../../../learning/text/tokenizer.dart';
import 'error_detectors.dart';
import 'language_issue.dart';

enum ConversationMode {
  guided('Rehberli', 'İpuçları, hazır ifadeler ve çeviriler açık. Düzeltmeler hemen gelir.'),
  practice('Alıştırma', 'Çeviri yok, ipucu istersen var. Kısa düzeltmeler hemen gelir.'),
  immersion('Almanca odaklı', 'Sadece Almanca. Düzeltmeleri konuşmanın sonunda topluca görürsün.'),
  challenge('Meydan okuma', 'İpucu yok, çeviri yok. Gerçek bir durum gibi; değerlendirme sonda.');

  const ConversationMode(this.labelTr, this.descriptionTr);
  final String labelTr;
  final String descriptionTr;

  bool get showsTranslations => this == guided;
  bool get offersHints => this != challenge;
  bool get showsHintsUpfront => this == guided;

  /// Accuracy-oriented modes correct after each turn; fluency-oriented
  /// modes collect corrections for the end review.
  bool get immediateFeedback => this == guided || this == practice;
}

enum Speaker { partner, learner }

class ConversationTurn {
  const ConversationTurn({
    required this.speaker,
    required this.de,
    this.tr,
    this.understood = true,
    this.issues = const [],
    this.goalReached,
  });

  final Speaker speaker;
  final String de;
  final String? tr;

  /// For learner turns: whether the partner could act on the message.
  final bool understood;
  final List<LanguageIssue> issues;
  final String? goalReached;

  Map<String, Object?> toJson() => {
        's': speaker.name,
        'de': de,
        if (tr != null) 'tr': tr,
        if (!understood) 'u': false,
        if (issues.isNotEmpty) 'i': [for (final i in issues) i.toJson()],
        if (goalReached != null) 'g': goalReached,
      };

  factory ConversationTurn.fromJson(Map<String, dynamic> j) => ConversationTurn(
        speaker: Speaker.values.byName(j['s'] as String),
        de: j['de'] as String,
        tr: j['tr'] as String?,
        understood: (j['u'] as bool?) ?? true,
        issues: [for (final i in (j['i'] as List?) ?? const []) LanguageIssue.fromJson((i as Map).cast<String, dynamic>())],
        goalReached: j['g'] as String?,
      );
}

class ConversationState {
  const ConversationState({
    required this.scenario,
    required this.mode,
    required this.turns,
    required this.goalsDone,
    required this.misunderstandings,
  });

  final Scenario scenario;
  final ConversationMode mode;
  final List<ConversationTurn> turns;
  final Set<String> goalsDone;
  final int misunderstandings;

  bool get isComplete => scenario.goals.every((g) => goalsDone.contains(g.id));

  ScenarioGoal? get nextGoal {
    for (final g in scenario.goals) {
      if (!goalsDone.contains(g.id)) return g;
    }
    return null;
  }

  List<LanguageIssue> get allIssues => [
        for (final t in turns)
          if (t.speaker == Speaker.learner) ...t.issues,
      ];

  ConversationState copyWith({List<ConversationTurn>? turns, Set<String>? goalsDone, int? misunderstandings, ConversationMode? mode}) =>
      ConversationState(
        scenario: scenario,
        mode: mode ?? this.mode,
        turns: turns ?? this.turns,
        goalsDone: goalsDone ?? this.goalsDone,
        misunderstandings: misunderstandings ?? this.misunderstandings,
      );
}

/// Produces the partner's reply to a learner message.
///
/// v0.1 ships only [OfflineScenarioEngine]. An AI-backed engine will
/// implement the same interface through the backend gateway
/// (docs/AI_DESIGN.md); the UI does not need to change.
abstract interface class ConversationEngine {
  ConversationState start(Scenario scenario, ConversationMode mode);
  Future<ConversationState> respond(ConversationState state, String learnerText);
}

/// Rule-based partner: recognises intents with patterns written for the
/// scenario, so it answers the *meaning* even when the German has errors,
/// and runs [ErrorDetectors] separately for feedback.
class OfflineScenarioEngine implements ConversationEngine {
  OfflineScenarioEngine(this.detectors);
  final ErrorDetectors detectors;

  @override
  ConversationState start(Scenario scenario, ConversationMode mode) => ConversationState(
        scenario: scenario,
        mode: mode,
        turns: [ConversationTurn(speaker: Speaker.partner, de: scenario.opening.de, tr: scenario.opening.tr)],
        goalsDone: const {},
        misunderstandings: 0,
      );

  @override
  Future<ConversationState> respond(ConversationState state, String learnerText) async {
    final text = learnerText.trim();
    if (text.isEmpty || state.isComplete) return state;
    final scenario = state.scenario;
    final issues = detectors.check(text, formalContext: scenario.formal, serviceContext: scenario.service);
    final folded = fold(text);

    final matched = <(ScenarioIntent, IntentMatch)>[];
    for (final intent in scenario.intents) {
      for (final m in intent.matches) {
        if (RegExp(m.pattern, caseSensitive: false).hasMatch(folded)) {
          matched.add((intent, m));
          break;
        }
      }
    }

    if (matched.isEmpty) {
      final fb = scenario.fallback[state.misunderstandings % scenario.fallback.length];
      return state.copyWith(
        turns: [
          ...state.turns,
          ConversationTurn(speaker: Speaker.learner, de: text, understood: false, issues: issues),
          ConversationTurn(speaker: Speaker.partner, de: fb.de, tr: fb.tr),
        ],
        misunderstandings: state.misunderstandings + 1,
      );
    }

    // Prefer intents that move the conversation forward.
    final done = {...state.goalsDone};
    (ScenarioIntent, IntentMatch)? replyFrom;
    String? reached;
    for (final (intent, m) in matched) {
      final goal = intent.goal;
      if (goal == null || done.contains(goal)) continue;
      if (!intent.requires.every(done.contains)) {
        replyFrom ??= (intent, m);
        continue;
      }
      done.add(goal);
      reached ??= goal;
      replyFrom = (intent, m);
    }
    replyFrom ??= matched.first;

    final (intent, m) = replyFrom;
    final blocked = intent.goal != null && !intent.requires.every(done.contains);
    final reply = blocked && intent.blocked != null ? intent.blocked! : m.reply;

    final turns = [
      ...state.turns,
      ConversationTurn(speaker: Speaker.learner, de: text, issues: issues, goalReached: reached),
      ConversationTurn(speaker: Speaker.partner, de: reply.de, tr: reply.tr),
    ];
    final next = state.copyWith(turns: turns, goalsDone: done);
    if (next.isComplete) {
      return next.copyWith(turns: [
        ...turns,
        ConversationTurn(speaker: Speaker.partner, de: scenario.closing.de, tr: scenario.closing.tr),
      ]);
    }
    return next;
  }
}
