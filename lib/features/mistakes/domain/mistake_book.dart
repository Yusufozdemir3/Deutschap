import '../../../content/content_bundle.dart';
import '../../../content/models/lesson.dart';
import '../../conversation/domain/language_issue.dart';
import '../../drill/domain/vocab_drill.dart';
import '../../progress/data/progress_repository.dart';

enum MistakeSource {
  lesson('Derslerde'),
  drill('Kelime antrenmanında'),
  listening('Dinlemede'),
  conversation('Konuşmalarda');

  const MistakeSource(this.labelTr);
  final String labelTr;
}

/// One thing the learner got wrong and has not yet got right since.
class Mistake {
  const Mistake({
    required this.source,
    required this.activityType,
    required this.itemId,
    required this.titleTr,
    required this.detail,
    required this.misses,
    required this.lastAt,
    this.correction,
    this.step,
  });

  final MistakeSource source;
  final String activityType;
  final String itemId;

  /// Where it happened ("Kafede sipariş", "der Termin · Artikel").
  final String titleTr;

  /// The item itself (German sentence or Turkish prompt).
  final String detail;

  /// Conversation mistakes: the corrected sentence.
  final String? correction;
  final int misses;
  final DateTime lastAt;

  /// A step that practises it again, if one can be rebuilt.
  final LessonStep? step;
}

/// Collects open mistakes from exercise attempts and conversation
/// corrections. A mistake closes as soon as the same item is answered
/// correctly (in a lesson, a drill or the review session).
class MistakeBook {
  MistakeBook(this.content);
  final ContentBundle content;

  /// Attempts of the review session for conversation mistakes.
  static const conversationFix = 'conversation_fix';
  static const _tracked = {'lesson', 'drill', 'listening', conversationFix};

  /// Step id used in the review: `mistake:<activityType>:<itemId>`.
  static String reviewStepId(String activityType, String itemId) => 'mistake:$activityType:$itemId';

  /// (activityType, itemId) from a review step id.
  static (String, String)? parseReviewStepId(String id) {
    if (!id.startsWith('mistake:')) return null;
    final rest = id.substring('mistake:'.length);
    final i = rest.indexOf(':');
    if (i < 0) return null;
    return (rest.substring(0, i), rest.substring(i + 1));
  }

  /// Stable key for a conversation correction.
  static String conversationKey(LanguageIssue i) {
    var h = 0x811c9dc5;
    for (final c in '${i.original}→${i.corrected}'.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  List<Mistake> open(List<AttemptRecord> attempts, List<ConversationRecord> conversations) {
    final steps = <String, (LessonStep, Lesson)>{
      for (final l in content.lessons)
        for (final s in l.steps) s.id: (s, l),
    };
    final drill = VocabDrillGenerator(content.lexicon);

    // Latest result and miss count per item.
    final latest = <String, AttemptRecord>{};
    final misses = <String, int>{};
    for (final a in attempts) {
      if (!_tracked.contains(a.activityType)) continue;
      final key = '${a.activityType}|${a.itemId}';
      latest[key] = a;
      if (!a.correct) misses[key] = (misses[key] ?? 0) + 1;
    }

    final out = <Mistake>[];
    for (final e in latest.entries) {
      final a = e.value;
      if (a.correct || a.activityType == conversationFix) continue;
      final m = _fromAttempt(a, misses[e.key] ?? 1, steps, drill);
      if (m != null) out.add(m);
    }

    // Conversation corrections stay open until the review answers them.
    final fixed = {
      for (final a in attempts)
        if (a.activityType == conversationFix && a.correct) a.itemId,
    };
    final seen = <String>{};
    for (final c in conversations) {
      for (final i in c.corrections) {
        if (i.severity != IssueSeverity.error || i.corrected == i.original) continue;
        final key = conversationKey(i);
        if (fixed.contains(key) || !seen.add(key)) continue;
        out.add(Mistake(
          source: MistakeSource.conversation,
          activityType: conversationFix,
          itemId: key,
          titleTr: content.scenario(c.scenarioId)?.titleTr ?? 'Konuşma',
          detail: i.original,
          correction: i.corrected,
          misses: 1,
          lastAt: c.updatedAt,
          step: ChoiceStep(
            reviewStepId(conversationFix, key),
            promptTr: 'Bir konuşmada şöyle yazmıştın. Hangisi doğru?',
            options: [i.corrected, i.original],
            answers: const [0],
            explainTr: i.explanationTr,
          ),
        ));
      }
    }

    out.sort((x, y) {
      final byMisses = y.misses.compareTo(x.misses);
      return byMisses != 0 ? byMisses : y.lastAt.compareTo(x.lastAt);
    });
    return out;
  }

  Mistake? _fromAttempt(AttemptRecord a, int misses, Map<String, (LessonStep, Lesson)> steps, VocabDrillGenerator drill) {
    final id = reviewStepId(a.activityType, a.itemId);
    switch (a.activityType) {
      case 'lesson':
        final found = steps[a.itemId];
        if (found == null) return null;
        final (step, lesson) = found;
        return Mistake(
          source: MistakeSource.lesson,
          activityType: a.activityType,
          itemId: a.itemId,
          titleTr: lesson.titleTr,
          detail: describe(step),
          misses: misses,
          lastAt: a.at,
          step: step is WriteStep ? null : stepWithId(step, id),
        );
      case 'drill':
        final parts = a.itemId.split(':');
        if (parts.length != 2) return null;
        final l = content.lexicon.byId(parts[0]);
        final mode = DrillMode.parse(parts[1]);
        if (l == null || mode == DrillMode.match || mode == DrillMode.mixed || !drill.supports(l, mode)) return null;
        final built = drill.build([l], mode: mode, size: 1, seed: a.at.millisecondsSinceEpoch).steps.firstOrNull;
        return Mistake(
          source: MistakeSource.drill,
          activityType: a.activityType,
          itemId: a.itemId,
          titleTr: '${l.headword} · ${mode.labelTr}',
          detail: l.tr,
          misses: misses,
          lastAt: a.at,
          step: built == null ? null : stepWithId(built, id),
        );
      case 'listening':
        final m = RegExp(r'^(.+)#q(\d+)$').firstMatch(a.itemId);
        if (m == null) return null;
        final track = content.track(m.group(1)!);
        final qi = int.parse(m.group(2)!);
        if (track == null || qi >= track.questions.length) return null;
        final q = track.questions[qi];
        return Mistake(
          source: MistakeSource.listening,
          activityType: a.activityType,
          itemId: a.itemId,
          titleTr: track.title,
          detail: q.questionTr,
          misses: misses,
          lastAt: a.at,
          step: ListenStep(id, de: track.lines.map((l) => l.de).join(' '), promptTr: q.questionTr, options: q.options, answers: [q.answer], explainTr: q.explainTr),
        );
    }
    return null;
  }

  /// A short, readable description of what a step asked.
  String describe(LessonStep s) => switch (s) {
        ChoiceStep() => s.de ?? s.promptTr,
        ClozeStep() => s.de,
        OrderStep() => s.tr,
        TranslateStep() => s.tr,
        ListenStep() => s.promptTr,
        ArticleStep() => content.lexicon.byId(s.lexemeId)?.headword ?? s.lexemeId,
        WriteStep() => s.promptTr,
        MatchStep() => s.promptTr ?? 'Eşleştirme',
        IntroStep() || GrammarStep() || DialogueStep() || TipStep() => '',
      };

  /// A review session over the most important open mistakes.
  Lesson review(List<Mistake> mistakes, {int max = 12}) => Lesson(
        id: 'mistakes',
        titleTr: 'Hatalarını düzelt',
        objectiveTr: 'Daha önce yanlış yaptığın soruları yeniden dene. Doğru cevapladığın hata defterden çıkar.',
        minutes: 5,
        steps: [for (final m in mistakes.where((m) => m.step != null).take(max)) m.step!],
      );
}
