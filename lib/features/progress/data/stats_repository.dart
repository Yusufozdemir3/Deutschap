import 'package:sqflite/sqflite.dart';

import '../../../core/clock.dart';

class LearningStats {
  const LearningStats({
    required this.unaidedRecallsThisWeek,
    required this.assistedRecallsThisWeek,
    required this.reviewsThisWeek,
    required this.delayedReviews,
    required this.delayedSuccesses,
    required this.productionSuccesses,
    required this.weeklyUnaided,
    required this.lessonsCompleted,
    required this.episodesCompleted,
    required this.scenariosCompleted,
    required this.contextsTotal,
  });

  final int unaidedRecallsThisWeek;
  final int assistedRecallsThisWeek;
  final int reviewsThisWeek;

  /// Reviews after a gap of at least 7 days, and how many succeeded.
  final int delayedReviews;
  final int delayedSuccesses;

  /// Typed German produced correctly without help (all time).
  final int productionSuccesses;

  /// Unaided recalls per week, oldest first (last 6 weeks).
  final List<int> weeklyUnaided;
  final int lessonsCompleted;
  final int episodesCompleted;
  final int scenariosCompleted;
  final int contextsTotal;

  double? get delayedRetention => delayedReviews == 0 ? null : delayedSuccesses / delayedReviews;
}

/// Evidence-based numbers for the progress screen. No screen time.
class StatsRepository {
  StatsRepository(this._db, {required Clock clock}) : _clock = clock;
  final Database _db;
  final Clock _clock;

  Future<int> _int(String sql, [List<Object?> args = const []]) async =>
      Sqflite.firstIntValue(await _db.rawQuery(sql, args)) ?? 0;

  Future<LearningStats> load() async {
    final now = _clock();
    final week = toMillis(startOfWeek(now));
    final weekly = <int>[];
    for (var i = 5; i >= 0; i--) {
      final from = startOfWeek(now).subtract(Duration(days: 7 * i));
      final to = from.add(const Duration(days: 7));
      weekly.add(await _int(
        'SELECT COUNT(*) FROM review_events WHERE assisted = 0 AND grade > 0 AND reviewed_at >= ? AND reviewed_at < ?',
        [toMillis(from), toMillis(to)],
      ));
    }
    return LearningStats(
      unaidedRecallsThisWeek: await _int('SELECT COUNT(*) FROM review_events WHERE assisted = 0 AND grade > 0 AND reviewed_at >= ?', [week]),
      assistedRecallsThisWeek: await _int('SELECT COUNT(*) FROM review_events WHERE assisted = 1 AND grade > 0 AND reviewed_at >= ?', [week]),
      reviewsThisWeek: await _int('SELECT COUNT(*) FROM review_events WHERE reviewed_at >= ?', [week]),
      delayedReviews: await _int('SELECT COUNT(*) FROM review_events WHERE prev_interval >= 7'),
      delayedSuccesses: await _int('SELECT COUNT(*) FROM review_events WHERE prev_interval >= 7 AND grade > 0 AND assisted = 0'),
      productionSuccesses: await _int("SELECT COUNT(*) FROM review_events WHERE card_type = 'production' AND grade > 0 AND assisted = 0"),
      weeklyUnaided: weekly,
      lessonsCompleted: await _int("SELECT COUNT(*) FROM lesson_progress WHERE status = 'completed'"),
      episodesCompleted: await _int("SELECT COUNT(*) FROM story_progress WHERE status = 'completed'"),
      scenariosCompleted: await _int("SELECT COUNT(DISTINCT scenario_id) FROM conversation_sessions WHERE status = 'completed'"),
      contextsTotal: await _int('SELECT COUNT(*) FROM vocab_contexts'),
    );
  }
}
