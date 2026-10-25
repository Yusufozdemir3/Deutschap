import 'package:sqflite/sqflite.dart';

import '../../../core/clock.dart';
import '../../vocabulary/domain/vocab_status.dart';
import '../../world/domain/world_progress.dart';

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

  Future<List<String>> _strings(String sql) async => [for (final r in await _db.rawQuery(sql)) r.values.first! as String];

  /// Everything the map, mystery board and milestones need, in one pass.
  Future<ProgressFacts> loadFacts({required int? Function(String episodeId) episodeNumber}) async {
    final counts = <VocabStatus, int>{
      for (final r in await _db.rawQuery('SELECT status, COUNT(*) AS n FROM vocab_entries GROUP BY status'))
        VocabStatus.parse(r['status']! as String): r['n']! as int,
    };
    return ProgressFacts(
      lessons: {...await _strings("SELECT lesson_id FROM lesson_progress WHERE status = 'completed'")},
      episodeNumbers: {
        for (final id in await _strings("SELECT episode_id FROM story_progress WHERE status = 'completed'")) ?episodeNumber(id),
      },
      scenarios: {...await _strings("SELECT DISTINCT scenario_id FROM conversation_sessions WHERE status = 'completed'")},
      readings: {...await _strings("SELECT DISTINCT ref_id FROM activity_log WHERE kind = 'reading' AND ref_id IS NOT NULL")},
      listenings: {...await _strings("SELECT DISTINCT ref_id FROM activity_log WHERE kind = 'listening' AND ref_id IS NOT NULL")},
      unaidedRecalls: await _int('SELECT COUNT(*) FROM review_events WHERE assisted = 0 AND grade > 0'),
      unaidedArticles: await _int("SELECT COUNT(*) FROM review_events WHERE assisted = 0 AND grade > 0 AND card_type = 'article'"),
      unaidedProductions: await _int("SELECT COUNT(*) FROM review_events WHERE assisted = 0 AND grade > 0 AND card_type = 'production'"),
      statusCounts: counts,
      recalledLexemes: {
        ...await _strings('SELECT DISTINCT e.lexeme_id FROM review_events ev JOIN vocab_entries e ON e.id = ev.entry_id '
            'WHERE ev.assisted = 0 AND ev.grade > 0 AND e.lexeme_id IS NOT NULL'),
      },
      savedLexemes: {...await _strings('SELECT lexeme_id FROM vocab_entries WHERE lexeme_id IS NOT NULL')},
    );
  }
}
