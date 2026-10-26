import '../../profile/domain/learner_profile.dart';

enum NotificationKind { study, review, weekly }

class PlannedNotification {
  const PlannedNotification({required this.id, required this.kind, required this.at, required this.title, required this.body, required this.route});
  final int id;
  final NotificationKind kind;
  final DateTime at;
  final String title;
  final String body;

  /// Where a tap opens the app.
  final String route;

  @override
  String toString() => '$kind@$at';
}

/// What the planner needs to know about the learner right now.
class NotificationFacts {
  const NotificationFacts({
    required this.now,
    required this.studiedToday,
    required this.nextReviewDue,
    required this.activeDaysThisWeek,
    required this.weeklyGoalDays,
  });
  final DateTime now;
  final bool studiedToday;

  /// Earliest due time of an active review card; null when there are none.
  final DateTime? nextReviewDue;
  final int activeDaysThisWeek;
  final int weeklyGoalDays;
}

/// Turns the learner's choices into concrete one-shot notifications for
/// the next [days] days. The app replaces the whole plan whenever data or
/// preferences change, so nothing here repeats on its own.
///
/// Rules (spec: ethical engagement): at most one notification per day,
/// never in quiet hours, nothing on a day the learner already studied,
/// no guilt or loss wording, and no learning details in the text so the
/// lock screen shows nothing personal.
class NotificationPlanner {
  const NotificationPlanner({this.days = 7});
  final int days;

  static const weeklyHour = 18;

  List<PlannedNotification> plan(NotificationPrefs prefs, NotificationFacts f) {
    final out = <PlannedNotification>[];
    final today = DateTime(f.now.year, f.now.month, f.now.day);
    final reminderHour = _awakeHour(prefs, prefs.reminderHour);
    for (var i = 0; i < days; i++) {
      final day = DateTime(today.year, today.month, today.day + i);
      if (i == 0 && f.studiedToday) continue;
      final slot = reminderHour == null ? null : DateTime(day.year, day.month, day.day, reminderHour);
      if (slot == null || !slot.isAfter(f.now)) continue;
      final reviewWaiting = f.nextReviewDue != null && !f.nextReviewDue!.isAfter(slot);
      if (prefs.reviewDue && reviewWaiting) {
        out.add(PlannedNotification(id: _id(day, NotificationKind.review), kind: NotificationKind.review, at: slot, title: 'Deutschap', body: 'Tekrar edilecek kelimelerin hazır. Birkaç dakika yeter.', route: '/review'));
      } else if (prefs.studyReminder) {
        out.add(PlannedNotification(id: _id(day, NotificationKind.study), kind: NotificationKind.study, at: slot, title: 'Deutschap', body: 'Bugün Almancaya birkaç dakika ayırmak ister misin?', route: '/heute'));
      }
    }
    if (prefs.weeklySummary) {
      final weekly = _weekly(prefs, f, today);
      if (weekly != null) {
        // The weekly summary takes the place of that day's reminder.
        out.removeWhere((n) => _sameDay(n.at, weekly.at));
        out.add(weekly);
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out;
  }

  PlannedNotification? _weekly(NotificationPrefs prefs, NotificationFacts f, DateTime today) {
    final hour = _awakeHour(prefs, weeklyHour) ?? _awakeHour(prefs, prefs.reminderHour);
    if (hour == null) return null;
    final sunday = DateTime(today.year, today.month, today.day + (DateTime.sunday - today.weekday));
    var at = DateTime(sunday.year, sunday.month, sunday.day, hour);
    final thisWeek = at.isAfter(f.now);
    if (!thisWeek) at = DateTime(sunday.year, sunday.month, sunday.day + 7, hour);
    // Next week's count is unknown yet; the plan is rebuilt before then.
    final body = thisWeek
        ? (f.activeDaysThisWeek >= f.weeklyGoalDays
            ? 'Bu hafta ${f.activeDaysThisWeek} gün çalıştın, hedefin ${f.weeklyGoalDays} gündü. Güzel bir hafta!'
            : 'Bu hafta ${f.activeDaysThisWeek} gün çalıştın. Haftalık özetin hazır.')
        : 'Haftalık özetin hazır.';
    return PlannedNotification(id: _id(at, NotificationKind.weekly), kind: NotificationKind.weekly, at: at, title: 'Haftan', body: body, route: '/progress');
  }

  /// [hour] if it is outside quiet hours, otherwise null.
  static int? _awakeHour(NotificationPrefs p, int hour) => isQuiet(p, hour) ? null : hour;

  /// Quiet hours run from `quietFrom` to `quietTo` and may cross midnight.
  static bool isQuiet(NotificationPrefs p, int hour) {
    if (p.quietFrom == p.quietTo) return false;
    return p.quietFrom < p.quietTo ? hour >= p.quietFrom && hour < p.quietTo : hour >= p.quietFrom || hour < p.quietTo;
  }

  static bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  /// Stable per day and kind, so rescheduling replaces instead of stacking.
  static int _id(DateTime day, NotificationKind k) => ((day.year % 100) * 10000 + day.month * 100 + day.day) * 10 + k.index;
}
