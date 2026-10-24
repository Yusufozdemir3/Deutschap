import 'package:deutschap/features/review/domain/scheduler.dart';
import 'package:deutschap/features/vocabulary/domain/vocab_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const scheduler = Scheduler();
  final t0 = DateTime(2026, 1, 1, 9);

  CardState answer(CardState s, Grade g, DateTime at, {bool assisted = false}) =>
      scheduler.review(s, g, assisted: assisted, now: at);

  group('Scheduler', () {
    test('first good answer schedules one day', () {
      final s = answer(CardState.initial(t0), Grade.good, t0);
      expect(s.intervalDays, 1);
      expect(s.reps, 1);
      expect(s.dueAt, t0.add(const Duration(days: 1)));
      expect(s.lastUnaidedSuccessAt, t0);
    });

    test('intervals grow on repeated success', () {
      var s = CardState.initial(t0);
      var at = t0;
      final intervals = <double>[];
      for (var i = 0; i < 5; i++) {
        s = answer(s, Grade.good, at);
        intervals.add(s.intervalDays);
        at = s.dueAt;
      }
      expect(intervals, orderedEquals([...intervals]..sort()));
      expect(intervals.last, greaterThan(20));
    });

    test('an assisted answer counts as hard and never raises ease', () {
      final base = answer(CardState.initial(t0), Grade.good, t0);
      final at = base.dueAt;
      final unaided = answer(base, Grade.easy, at);
      final assisted = answer(base, Grade.easy, at, assisted: true);
      expect(assisted.intervalDays, lessThan(unaided.intervalDays));
      expect(assisted.ease, lessThanOrEqualTo(base.ease));
      expect(assisted.lastUnaidedSuccessAt, base.lastUnaidedSuccessAt, reason: 'help is not unaided recall');
    });

    test('a failure resets to a short relearning step and counts a lapse', () {
      var s = answer(CardState.initial(t0), Grade.good, t0);
      s = answer(s, Grade.good, s.dueAt);
      final failed = answer(s, Grade.again, s.dueAt);
      expect(failed.reps, 0);
      expect(failed.lapses, 1);
      expect(failed.dueAt.difference(s.dueAt), const Duration(minutes: Scheduler.relearnMinutes));
      expect(failed.ease, lessThan(s.ease));
    });

    test('early success does not lengthen the interval', () {
      final s = answer(CardState.initial(t0), Grade.good, t0);
      final early = answer(s, Grade.easy, t0.add(const Duration(hours: 2)));
      expect(early.intervalDays, s.intervalDays);
      expect(early.dueAt, s.dueAt);
    });

    test('ease stays within bounds', () {
      var s = CardState.initial(t0);
      var at = t0;
      for (var i = 0; i < 30; i++) {
        s = answer(s, Grade.again, at);
        at = s.dueAt;
      }
      expect(s.ease, Scheduler.minEase);
    });
  });

  group('deriveStatus', () {
    test('a single correct answer is never mastery', () {
      final s = answer(CardState.initial(t0), Grade.easy, t0);
      final status = deriveStatus(paused: false, cards: [s], delayedUnaidedSuccesses: 0);
      expect(status, VocabStatus.learning);
    });

    test('new until first review, paused shows saved-for-later', () {
      final c = CardState.initial(t0);
      expect(deriveStatus(paused: false, cards: [c], delayedUnaidedSuccesses: 0), VocabStatus.newlyEncountered);
      expect(deriveStatus(paused: true, cards: [c], delayedUnaidedSuccesses: 0), VocabStatus.savedForLater);
    });

    test('a recent failure needs reinforcement', () {
      final s = answer(answer(CardState.initial(t0), Grade.good, t0), Grade.again, t0.add(const Duration(days: 1)));
      expect(deriveStatus(paused: false, cards: [s], delayedUnaidedSuccesses: 0), VocabStatus.needsReinforcement);
    });

    test('long-term retention needs long intervals, several card types and delayed evidence', () {
      CardState long(double days) => CardState(ease: 2.5, intervalDays: days, reps: 6, lapses: 0, dueAt: t0, lastReviewedAt: t0, lastGrade: Grade.good);
      expect(deriveStatus(paused: false, cards: [long(70)], delayedUnaidedSuccesses: 5), VocabStatus.temporarilyMastered);
      expect(deriveStatus(paused: false, cards: [long(70), long(80)], delayedUnaidedSuccesses: 1), VocabStatus.temporarilyMastered);
      expect(deriveStatus(paused: false, cards: [long(70), long(80)], delayedUnaidedSuccesses: 2), VocabStatus.longTermRetained);
      expect(deriveStatus(paused: false, cards: [long(10), long(80)], delayedUnaidedSuccesses: 2), VocabStatus.familiar);
    });
  });
}
