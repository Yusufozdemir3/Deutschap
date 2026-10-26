import 'package:deutschap/features/notifications/domain/notification_planner.dart';
import 'package:deutschap/features/profile/domain/learner_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const planner = NotificationPlanner();
  // Wednesday 4 March 2026, 10:00.
  final now = DateTime(2026, 3, 4, 10);
  NotificationFacts facts({bool studied = false, DateTime? due, int active = 1}) =>
      NotificationFacts(now: now, studiedToday: studied, nextReviewDue: due, activeDaysThisWeek: active, weeklyGoalDays: 3);

  test('nothing is planned while every category is off', () {
    expect(planner.plan(const NotificationPrefs(), facts(due: now)), isEmpty);
  });

  test('study reminder: once a day at the chosen hour, skipping a day already studied', () {
    const prefs = NotificationPrefs(studyReminder: true, reminderHour: 19);
    final plan = planner.plan(prefs, facts(studied: true));
    expect(plan.length, 6);
    expect(plan.first.at, DateTime(2026, 3, 5, 19));
    expect(plan.map((n) => n.id).toSet().length, plan.length);
    expect(planner.plan(prefs, facts()).first.at, DateTime(2026, 3, 4, 19));
  });

  test('review reminder replaces the study reminder only once cards are due', () {
    const prefs = NotificationPrefs(studyReminder: true, reviewDue: true, reminderHour: 19);
    final plan = planner.plan(prefs, facts(due: DateTime(2026, 3, 6, 8)));
    final kinds = {for (final n in plan) n.at.day: n.kind};
    expect(kinds[4], NotificationKind.study);
    expect(kinds[5], NotificationKind.study);
    expect(kinds[6], NotificationKind.review);
    expect(plan.where((n) => n.kind == NotificationKind.review).first.route, '/review');
  });

  test('reminders inside quiet hours are dropped, quiet hours may cross midnight', () {
    const prefs = NotificationPrefs(studyReminder: true, reminderHour: 22, quietFrom: 21, quietTo: 7);
    expect(planner.plan(prefs, facts()), isEmpty);
    expect(NotificationPlanner.isQuiet(prefs, 3), isTrue);
    expect(NotificationPlanner.isQuiet(prefs, 12), isFalse);
    const day = NotificationPrefs(quietFrom: 12, quietTo: 14);
    expect(NotificationPlanner.isQuiet(day, 13), isTrue);
    expect(NotificationPlanner.isQuiet(day, 15), isFalse);
  });

  test('weekly summary on Sunday evening replaces that day\'s reminder', () {
    const prefs = NotificationPrefs(studyReminder: true, weeklySummary: true, reminderHour: 19);
    final plan = planner.plan(prefs, facts(active: 3));
    final sunday = plan.where((n) => n.at.day == 8).toList();
    expect(sunday.single.kind, NotificationKind.weekly);
    expect(sunday.single.at, DateTime(2026, 3, 8, 18));
    expect(sunday.single.body, contains('3 gün'));
  });

  test('texts carry no guilt or loss wording', () {
    const prefs = NotificationPrefs(studyReminder: true, reviewDue: true, weeklySummary: true);
    for (final n in planner.plan(prefs, facts(due: now, active: 0))) {
      expect(n.body.toLowerCase(), isNot(anyOf(contains('kaybed'), contains('seri'), contains('kaçır'))));
    }
  });
}
