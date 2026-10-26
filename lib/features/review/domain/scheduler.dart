import 'dart:math' as math;

/// How well the learner recalled an item.
enum Grade {
  again(0),
  hard(1),
  good(2),
  easy(3);

  const Grade(this.value);
  final int value;
  static Grade of(int v) => Grade.values.firstWhere((g) => g.value == v);
  bool get isSuccess => this != again;
}

/// What is being practised for an entry. Each type is scheduled separately
/// because recognising a word and producing it are different skills.
enum CardType {
  /// German → meaning (self-graded).
  recognition,

  /// Turkish meaning → typed German (auto-graded).
  production,

  /// Noun → der/die/das (auto-graded).
  article,

  /// Saved sentence with one word blanked → type the word (auto-graded).
  cloze;

  static CardType parse(String s) => CardType.values.byName(s);
}

class CardState {
  const CardState({
    required this.ease,
    required this.intervalDays,
    required this.reps,
    required this.lapses,
    required this.dueAt,
    this.lastReviewedAt,
    this.lastUnaidedSuccessAt,
    this.lastGrade,
  });

  /// New card, due immediately.
  factory CardState.initial(DateTime now) =>
      CardState(ease: Scheduler.startEase, intervalDays: 0, reps: 0, lapses: 0, dueAt: now);

  final double ease;
  final double intervalDays;

  /// Consecutive successful reviews since the last lapse.
  final int reps;
  final int lapses;
  final DateTime dueAt;
  final DateTime? lastReviewedAt;
  final DateTime? lastUnaidedSuccessAt;
  final Grade? lastGrade;

  bool isDue(DateTime now) => !dueAt.isAfter(now);

  CardState copyWith({
    double? ease,
    double? intervalDays,
    int? reps,
    int? lapses,
    DateTime? dueAt,
    DateTime? lastReviewedAt,
    DateTime? lastUnaidedSuccessAt,
    Grade? lastGrade,
  }) =>
      CardState(
        ease: ease ?? this.ease,
        intervalDays: intervalDays ?? this.intervalDays,
        reps: reps ?? this.reps,
        lapses: lapses ?? this.lapses,
        dueAt: dueAt ?? this.dueAt,
        lastReviewedAt: lastReviewedAt ?? this.lastReviewedAt,
        lastUnaidedSuccessAt: lastUnaidedSuccessAt ?? this.lastUnaidedSuccessAt,
        lastGrade: lastGrade ?? this.lastGrade,
      );
}

/// A transparent SM-2 derivative. Documented in docs/REVIEW_ENGINE.md.
///
/// Deliberate differences from plain SM-2:
/// * An answer given after a hint ([assisted]) counts at most as "hard"
///   and never raises ease.
/// * Reviewing before the due date does not lengthen the interval: an
///   early correct answer is not evidence of long-term retention.
///   A failure still counts.
/// * Intervals are capped, and a lapse resets to a short relearning step.
class Scheduler {
  const Scheduler();

  static const startEase = 2.5;
  static const minEase = 1.3;
  static const maxEase = 3.0;
  static const maxIntervalDays = 365.0;
  static const relearnMinutes = 10;

  CardState review(CardState s, Grade grade, {required bool assisted, required DateTime now}) {
    final effective = assisted && grade.isSuccess ? Grade.hard : grade;

    if (!effective.isSuccess) {
      return s.copyWith(
        ease: math.max(minEase, s.ease - 0.2),
        intervalDays: relearnMinutes / (24 * 60),
        reps: 0,
        lapses: s.reps > 0 || s.intervalDays >= 1 ? s.lapses + 1 : s.lapses,
        dueAt: now.add(const Duration(minutes: relearnMinutes)),
        lastReviewedAt: now,
        lastGrade: grade,
      );
    }

    final unaidedAt = assisted ? s.lastUnaidedSuccessAt : now;

    if (!s.isDue(now) && s.reps > 0) {
      // Early success: keep the schedule, only record the observation.
      return s.copyWith(lastReviewedAt: now, lastUnaidedSuccessAt: unaidedAt, lastGrade: grade);
    }

    final double next;
    var ease = s.ease;
    switch (s.reps) {
      case 0:
        next = switch (effective) { Grade.hard => 0.5, Grade.good => 1, _ => 3 };
      case 1:
        next = switch (effective) { Grade.hard => 2, Grade.good => 3, _ => 6 };
      default:
        final base = math.max(s.intervalDays, 1.0);
        switch (effective) {
          case Grade.hard:
            next = base * 1.2;
            ease -= 0.15;
          case Grade.good:
            next = base * s.ease;
          default:
            next = base * s.ease * 1.3;
            ease += 0.15;
        }
    }
    if (assisted) ease = math.min(ease, s.ease);
    final interval = math.min(maxIntervalDays, next);
    return s.copyWith(
      ease: ease.clamp(minEase, maxEase),
      intervalDays: interval,
      reps: s.reps + 1,
      dueAt: now.add(Duration(minutes: (interval * 24 * 60).round())),
      lastReviewedAt: now,
      lastUnaidedSuccessAt: unaidedAt,
      lastGrade: grade,
    );
  }
}
