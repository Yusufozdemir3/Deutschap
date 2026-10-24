import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/clock.dart';
import '../../conversation/domain/language_issue.dart';
import '../../home/domain/recommender.dart';
import '../../stories/domain/story_runner.dart';

enum LessonStatus { notStarted, inProgress, completed }

class LessonProgress {
  const LessonProgress({required this.lessonId, required this.status, this.stepIndex = 0, this.correct = 0, this.total = 0, this.completedAt});
  final String lessonId;
  final LessonStatus status;
  final int stepIndex;
  final int correct;
  final int total;
  final DateTime? completedAt;
}

enum EpisodeStatus { inProgress, completed }

class EpisodeProgress {
  const EpisodeProgress({
    required this.episodeId,
    required this.storyId,
    required this.nodeId,
    required this.flags,
    required this.history,
    required this.status,
    this.quizCorrect,
    this.quizTotal,
    this.completedAt,
    this.updatedAt,
  });
  final String episodeId;
  final String storyId;
  final String nodeId;
  final Set<String> flags;
  final List<StoryStep> history;
  final EpisodeStatus status;
  final int? quizCorrect;
  final int? quizTotal;
  final DateTime? completedAt;
  final DateTime? updatedAt;
}

class ConversationRecord {
  const ConversationRecord({required this.id, required this.scenarioId, required this.mode, required this.status, required this.goalsDone, required this.corrections, required this.updatedAt, this.transcript});
  final String id;
  final String scenarioId;
  final String mode;
  final String status;
  final List<String> goalsDone;
  final List<LanguageIssue> corrections;
  final String? transcript;
  final DateTime updatedAt;
}

class ActivityRecord {
  const ActivityRecord({required this.kind, required this.at, this.refId, this.summary});
  final ActivityKind kind;
  final String? refId;
  final String? summary;
  final DateTime at;
}

/// Progress through lessons, story episodes and scenarios, plus the
/// activity log behind weekly goals.
class ProgressRepository {
  ProgressRepository(this._db, {required Clock clock, required IdGenerator ids})
      : _clock = clock,
        _ids = ids;
  final Database _db;
  final Clock _clock;
  final IdGenerator _ids;

  // ---------------------------------------------------------------- lessons

  Future<Map<String, LessonProgress>> lessonProgress() async {
    final r = await _db.query('lesson_progress');
    return {for (final row in r) row['lesson_id']! as String: _lesson(row)};
  }

  Future<LessonProgress?> lesson(String id) async {
    final r = await _db.query('lesson_progress', where: 'lesson_id = ?', whereArgs: [id]);
    return r.isEmpty ? null : _lesson(r.first);
  }

  /// Saves the position after each step so an interrupted lesson resumes.
  Future<void> saveLessonStep(String lessonId, {required int stepIndex, required int correct, required int total}) async {
    final existing = await lesson(lessonId);
    if (existing?.status == LessonStatus.completed) {
      await _db.update('lesson_progress', {'step_index': stepIndex, 'updated_at': toMillis(_clock())},
          where: 'lesson_id = ?', whereArgs: [lessonId]);
      return;
    }
    await _db.insert(
      'lesson_progress',
      {
        'lesson_id': lessonId,
        'status': LessonStatus.inProgress.name,
        'step_index': stepIndex,
        'correct': correct,
        'total': total,
        'updated_at': toMillis(_clock()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> completeLesson(String lessonId, {required int correct, required int total}) async {
    final now = _clock();
    await _db.transaction((txn) async {
      final prev = await txn.query('lesson_progress', where: 'lesson_id = ?', whereArgs: [lessonId]);
      final firstCompletion = prev.isEmpty || prev.first['status'] != LessonStatus.completed.name;
      await txn.insert(
        'lesson_progress',
        {
          'lesson_id': lessonId,
          'status': LessonStatus.completed.name,
          'step_index': 0,
          'correct': correct,
          'total': total,
          'completed_at': firstCompletion ? toMillis(now) : prev.first['completed_at'],
          'updated_at': toMillis(now),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await _log(txn, ActivityKind.lesson, lessonId, '$correct/$total', now);
    });
  }

  Future<void> recordAttempt({required String activityType, required String activityId, required String itemId, required bool correct, required bool assisted}) async {
    await _db.insert('exercise_attempts', {
      'id': _ids(),
      'activity_type': activityType,
      'activity_id': activityId,
      'item_id': itemId,
      'correct': correct ? 1 : 0,
      'assisted': assisted ? 1 : 0,
      'created_at': toMillis(_clock()),
    });
  }

  // ---------------------------------------------------------------- stories

  Future<Map<String, EpisodeProgress>> episodeProgress() async {
    final r = await _db.query('story_progress');
    return {for (final row in r) row['episode_id']! as String: _episode(row)};
  }

  Future<EpisodeProgress?> episode(String id) async {
    final r = await _db.query('story_progress', where: 'episode_id = ?', whereArgs: [id]);
    return r.isEmpty ? null : _episode(r.first);
  }

  Future<void> saveEpisodeState(String episodeId, String storyId, StoryState s) async {
    final existing = await episode(episodeId);
    await _db.insert(
      'story_progress',
      {
        'episode_id': episodeId,
        'story_id': storyId,
        'node_id': s.nodeId,
        'flags': jsonEncode(s.flags.toList()),
        'history': jsonEncode([for (final h in s.history) h.toJson()]),
        // Replaying a completed episode keeps it completed.
        'status': existing?.status == EpisodeStatus.completed ? EpisodeStatus.completed.name : EpisodeStatus.inProgress.name,
        'quiz_correct': existing?.quizCorrect,
        'quiz_total': existing?.quizTotal,
        'completed_at': existing?.completedAt == null ? null : toMillis(existing!.completedAt!),
        'updated_at': toMillis(_clock()),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> completeEpisode(String episodeId, {required int quizCorrect, required int quizTotal}) async {
    final now = _clock();
    await _db.transaction((txn) async {
      final prev = await txn.query('story_progress', where: 'episode_id = ?', whereArgs: [episodeId]);
      if (prev.isEmpty) return;
      final first = prev.first['status'] != EpisodeStatus.completed.name;
      await txn.update(
        'story_progress',
        {
          'status': EpisodeStatus.completed.name,
          'quiz_correct': quizCorrect,
          'quiz_total': quizTotal,
          if (first) 'completed_at': toMillis(now),
          'updated_at': toMillis(now),
        },
        where: 'episode_id = ?',
        whereArgs: [episodeId],
      );
      if (first) await _log(txn, ActivityKind.story, episodeId, '$quizCorrect/$quizTotal', now);
    });
  }

  Future<void> resetEpisode(String episodeId) async {
    final e = await episode(episodeId);
    if (e == null) return;
    if (e.status == EpisodeStatus.completed) {
      // Keep completion, restart position for a replay.
      await _db.update('story_progress', {'node_id': '', 'history': '[]', 'flags': '[]', 'updated_at': toMillis(_clock())},
          where: 'episode_id = ?', whereArgs: [episodeId]);
    } else {
      await _db.delete('story_progress', where: 'episode_id = ?', whereArgs: [episodeId]);
    }
  }

  // ---------------------------------------------------------- conversations

  Future<void> saveConversation({
    required String id,
    required String scenarioId,
    required String mode,
    required bool completed,
    required List<String> goalsDone,
    required List<LanguageIssue> corrections,
    String? transcript,
  }) async {
    final now = _clock();
    await _db.transaction((txn) async {
      final prev = await txn.query('conversation_sessions', columns: ['status', 'created_at'], where: 'id = ?', whereArgs: [id]);
      await txn.insert(
        'conversation_sessions',
        {
          'id': id,
          'scenario_id': scenarioId,
          'mode': mode,
          'status': completed ? 'completed' : 'active',
          'transcript': transcript,
          'goals_done': jsonEncode(goalsDone),
          'corrections': jsonEncode([for (final c in corrections) c.toJson()]),
          'created_at': prev.isEmpty ? toMillis(now) : prev.first['created_at'],
          'updated_at': toMillis(now),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      final wasCompleted = prev.isNotEmpty && prev.first['status'] == 'completed';
      if (completed && !wasCompleted) await _log(txn, ActivityKind.scenario, scenarioId, null, now);
    });
  }

  Future<Set<String>> completedScenarioIds() async {
    final r = await _db.rawQuery("SELECT DISTINCT scenario_id FROM conversation_sessions WHERE status = 'completed'");
    return {for (final row in r) row['scenario_id']! as String};
  }

  Future<List<ConversationRecord>> conversations({int limit = 20}) async {
    final r = await _db.query('conversation_sessions', orderBy: 'updated_at DESC', limit: limit);
    return [
      for (final row in r)
        ConversationRecord(
          id: row['id']! as String,
          scenarioId: row['scenario_id']! as String,
          mode: row['mode']! as String,
          status: row['status']! as String,
          goalsDone: (jsonDecode(row['goals_done']! as String) as List).cast<String>(),
          corrections: [
            for (final c in jsonDecode(row['corrections']! as String) as List) LanguageIssue.fromJson((c as Map).cast<String, dynamic>()),
          ],
          transcript: row['transcript'] as String?,
          updatedAt: fromMillis(row['updated_at']! as int),
        ),
    ];
  }

  /// Most frequent correction rules (recurring difficulties).
  Future<Map<String, int>> recurringIssues() async {
    final counts = <String, int>{};
    for (final c in await conversations(limit: 100)) {
      for (final i in c.corrections) {
        if (i.severity == IssueSeverity.error) counts[i.ruleId] = (counts[i.ruleId] ?? 0) + 1;
      }
    }
    return counts;
  }

  Future<void> deleteConversationHistory() => _db.delete('conversation_sessions');

  // ---------------------------------------------------------------- activity

  Future<void> logActivity(ActivityKind kind, {String? refId, String? summary}) =>
      _log(_db, kind, refId, summary, _clock());

  Future<void> _log(DatabaseExecutor ex, ActivityKind kind, String? refId, String? summary, DateTime at) =>
      ex.insert('activity_log', {'id': _ids(), 'kind': kind.name, 'ref_id': refId, 'summary': summary, 'created_at': toMillis(at)});

  Future<List<ActivityRecord>> recentActivity({int limit = 10}) async {
    final r = await _db.query('activity_log', orderBy: 'created_at DESC', limit: limit);
    return [
      for (final row in r)
        ActivityRecord(
          kind: ActivityKind.values.byName(row['kind']! as String),
          refId: row['ref_id'] as String?,
          summary: row['summary'] as String?,
          at: fromMillis(row['created_at']! as int),
        ),
    ];
  }

  /// Distinct calendar days with any learning (activity or review) since [from].
  Future<Set<DateTime>> activeDays(DateTime from) async {
    final ms = toMillis(from);
    final a = await _db.rawQuery('SELECT created_at AS t FROM activity_log WHERE created_at >= ?', [ms]);
    final b = await _db.rawQuery('SELECT reviewed_at AS t FROM review_events WHERE reviewed_at >= ?', [ms]);
    return {
      for (final row in [...a, ...b])
        () {
          final d = fromMillis(row['t']! as int);
          return DateTime(d.year, d.month, d.day);
        }(),
    };
  }

  // ---------------------------------------------------------------- mapping

  static LessonProgress _lesson(Map<String, Object?> r) => LessonProgress(
        lessonId: r['lesson_id']! as String,
        status: LessonStatus.values.byName(r['status']! as String),
        stepIndex: r['step_index']! as int,
        correct: r['correct']! as int,
        total: r['total']! as int,
        completedAt: r['completed_at'] == null ? null : fromMillis(r['completed_at']! as int),
      );

  static EpisodeProgress _episode(Map<String, Object?> r) => EpisodeProgress(
        episodeId: r['episode_id']! as String,
        storyId: r['story_id']! as String,
        nodeId: r['node_id']! as String,
        flags: {...(jsonDecode(r['flags']! as String) as List).cast<String>()},
        history: [for (final h in jsonDecode(r['history']! as String) as List) StoryStep.fromJson((h as Map).cast<String, dynamic>())],
        status: EpisodeStatus.values.byName(r['status']! as String),
        quizCorrect: r['quiz_correct'] as int?,
        quizTotal: r['quiz_total'] as int?,
        completedAt: r['completed_at'] == null ? null : fromMillis(r['completed_at']! as int),
        updatedAt: fromMillis(r['updated_at']! as int),
      );
}
