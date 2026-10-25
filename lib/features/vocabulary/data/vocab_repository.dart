import 'package:sqflite/sqflite.dart';

import '../../../content/models/lexeme.dart';
import '../../../core/clock.dart';
import '../../review/domain/scheduler.dart';
import '../domain/vocab_entry.dart';
import '../domain/vocab_status.dart';

enum VocabSort { recent, alphabetical, status }

class VocabQuery {
  const VocabQuery({this.text = '', this.status, this.kind, this.collectionId, this.sort = VocabSort.recent, this.limit = 50, this.offset = 0});
  final String text;
  final VocabStatus? status;
  final String? kind;
  final String? collectionId;
  final VocabSort sort;
  final int limit;
  final int offset;
}

/// Learner-owned vocabulary: entries, contexts, review cards, events and
/// collections. All multi-step writes run in a transaction.
class VocabRepository {
  VocabRepository(this._db, {required Clock clock, required IdGenerator ids, Scheduler scheduler = const Scheduler()})
      : _clock = clock,
        _ids = ids,
        _scheduler = scheduler;

  final Database _db;
  final Clock _clock;
  final IdGenerator _ids;
  final Scheduler _scheduler;

  // ---------------------------------------------------------------- saving

  /// Saves a curated lexeme (or adds a new context if already saved).
  /// Returns the entry and whether it existed before.
  Future<(VocabEntry, bool existed)> saveLexeme(Lexeme l, {SourceContext? context}) async {
    final now = _clock();
    return _db.transaction((txn) async {
      final existing = await txn.query('vocab_entries', where: 'lexeme_id = ?', whereArgs: [l.id], limit: 1);
      if (existing.isNotEmpty) {
        final entry = _entry(existing.first);
        if (context != null) await _insertContext(txn, entry.id, context, now);
        return (entry, true);
      }
      final id = _ids();
      await txn.insert('vocab_entries', {
        'id': id,
        'lexeme_id': l.id,
        'headword': l.headword,
        'lemma': l.lemma,
        'kind': l.pos.name,
        'article': l.article,
        'plural': l.plural,
        'meaning_tr': l.tr,
        'meaning_en': l.en,
        'status': VocabStatus.newlyEncountered.key,
        'created_at': toMillis(now),
        'updated_at': toMillis(now),
      });
      await _insertCard(txn, id, CardType.recognition, now);
      if (l.isNoun && l.article != null && !l.tags.contains('proper')) {
        await _insertCard(txn, id, CardType.article, now);
      }
      if (context != null) await _insertContext(txn, id, context, now);
      final row = await txn.query('vocab_entries', where: 'id = ?', whereArgs: [id]);
      return (_entry(row.first), false);
    });
  }

  Future<VocabEntry> saveManual({
    required String headword,
    required String meaningTr,
    String kind = 'expression',
    String? article,
    String? plural,
    String? note,
    SourceContext? context,
  }) async {
    final now = _clock();
    final id = _ids();
    final lemma = article != null && headword.startsWith('$article ') ? headword.substring(article.length + 1) : headword;
    await _db.transaction((txn) async {
      await txn.insert('vocab_entries', {
        'id': id,
        'lexeme_id': null,
        'headword': headword.trim(),
        'lemma': lemma.trim(),
        'kind': kind,
        'article': article,
        'plural': plural,
        'meaning_tr': meaningTr.trim(),
        'note': note,
        'status': VocabStatus.newlyEncountered.key,
        'created_at': toMillis(now),
        'updated_at': toMillis(now),
      });
      await _insertCard(txn, id, CardType.recognition, now);
      if (kind == 'noun' && article != null) await _insertCard(txn, id, CardType.article, now);
      if (context != null) await _insertContext(txn, id, context, now);
    });
    return (await entry(id))!;
  }

  Future<void> addContext(String entryId, SourceContext context) =>
      _insertContext(_db, entryId, context, _clock());

  Future<void> _insertContext(DatabaseExecutor ex, String entryId, SourceContext c, DateTime now) async {
    await ex.insert(
      'vocab_contexts',
      {
        'id': _ids(),
        'entry_id': entryId,
        'source_type': c.type.name,
        'source_id': c.sourceId,
        'source_title': c.title,
        'sentence': c.sentence,
        'sentence_tr': c.sentenceTr,
        'created_at': toMillis(now),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<void> _insertCard(DatabaseExecutor ex, String entryId, CardType type, DateTime dueAt) async {
    final s = CardState.initial(dueAt);
    await ex.insert(
      'review_cards',
      {
        'entry_id': entryId,
        'card_type': type.name,
        'ease': s.ease,
        'interval_days': s.intervalDays,
        'reps': s.reps,
        'lapses': s.lapses,
        'due_at': toMillis(s.dueAt),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  // --------------------------------------------------------------- reading

  Future<VocabEntry?> entry(String id) async {
    final r = await _db.query('vocab_entries', where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : _entry(r.first);
  }

  Future<VocabEntry?> entryByLexeme(String lexemeId) async {
    final r = await _db.query('vocab_entries', where: 'lexeme_id = ?', whereArgs: [lexemeId], limit: 1);
    return r.isEmpty ? null : _entry(r.first);
  }

  Future<Set<String>> savedLexemeIds() async {
    final r = await _db.rawQuery('SELECT lexeme_id FROM vocab_entries WHERE lexeme_id IS NOT NULL');
    return {for (final row in r) row['lexeme_id']! as String};
  }

  Future<List<SourceContext>> contexts(String entryId) async {
    final r = await _db.query('vocab_contexts', where: 'entry_id = ?', whereArgs: [entryId], orderBy: 'created_at DESC');
    return r.map(_context).toList();
  }

  Future<List<ReviewCard>> cards(String entryId) async {
    final r = await _db.query('review_cards', where: 'entry_id = ?', whereArgs: [entryId]);
    return r.map(_card).toList();
  }

  Future<int> count() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM vocab_entries')) ?? 0;

  Future<List<VocabEntry>> list(VocabQuery q) async {
    final where = <String>[];
    final args = <Object?>[];
    if (q.text.trim().isNotEmpty) {
      where.add('(e.headword LIKE ? OR e.meaning_tr LIKE ? OR e.meaning_en LIKE ? OR e.note LIKE ?)');
      final like = '%${q.text.trim()}%';
      args.addAll([like, like, like, like]);
    }
    if (q.status != null) {
      where.add('e.status = ?');
      args.add(q.status!.key);
    }
    if (q.kind != null) {
      where.add('e.kind = ?');
      args.add(q.kind);
    }
    var from = 'vocab_entries e';
    if (q.collectionId != null) {
      from += ' JOIN collection_items ci ON ci.entry_id = e.id AND ci.collection_id = ?';
      args.insert(0, q.collectionId);
    }
    final order = switch (q.sort) {
      VocabSort.recent => 'e.created_at DESC',
      VocabSort.alphabetical => 'e.lemma COLLATE NOCASE ASC',
      VocabSort.status => 'e.status ASC, e.updated_at DESC',
    };
    final sql = 'SELECT e.* FROM $from${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'} ORDER BY $order LIMIT ? OFFSET ?';
    final r = await _db.rawQuery(sql, [...args, q.limit, q.offset]);
    return r.map(_entry).toList();
  }

  Future<Map<VocabStatus, int>> statusCounts() async {
    final r = await _db.rawQuery('SELECT status, COUNT(*) AS n FROM vocab_entries GROUP BY status');
    return {for (final row in r) VocabStatus.parse(row['status']! as String): row['n']! as int};
  }

  // --------------------------------------------------------------- editing

  Future<void> updateNote(String entryId, String? note) async {
    await _db.update('vocab_entries', {'note': (note?.trim().isEmpty ?? true) ? null : note!.trim(), 'updated_at': toMillis(_clock())},
        where: 'id = ?', whereArgs: [entryId]);
  }

  Future<void> updateMeaning(String entryId, String meaningTr) async {
    if (meaningTr.trim().isEmpty) return;
    await _db.update('vocab_entries', {'meaning_tr': meaningTr.trim(), 'updated_at': toMillis(_clock())},
        where: 'id = ?', whereArgs: [entryId]);
  }

  Future<void> setPaused(String entryId, bool paused) async {
    await _db.transaction((txn) async {
      await txn.update('vocab_entries', {'paused': paused ? 1 : 0, 'updated_at': toMillis(_clock())},
          where: 'id = ?', whereArgs: [entryId]);
      await _refreshStatus(txn, entryId);
    });
  }

  /// Removes the entry with its contexts, cards, events and memberships.
  Future<void> delete(String entryId) async {
    await _db.delete('vocab_entries', where: 'id = ?', whereArgs: [entryId]);
  }

  // ---------------------------------------------------------------- review

  Future<int> dueCount() async {
    final now = toMillis(_clock());
    return Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COUNT(*) FROM review_cards c JOIN vocab_entries e ON e.id = c.entry_id '
          'WHERE e.paused = 0 AND c.due_at <= ?',
          [now],
        )) ??
        0;
  }

  /// Due cards, oldest first, at most one card per entry per session so a
  /// word's article and meaning are not asked back to back.
  Future<List<DueItem>> dueItems({int limit = 20, Set<String> onlyEntries = const {}}) async {
    final now = toMillis(_clock());
    final filter = onlyEntries.isEmpty ? '' : ' AND e.id IN (${List.filled(onlyEntries.length, '?').join(',')})';
    final rows = await _db.rawQuery(
      'SELECT c.*, e.* FROM review_cards c JOIN vocab_entries e ON e.id = c.entry_id '
      'WHERE e.paused = 0 AND c.due_at <= ?$filter ORDER BY c.due_at ASC LIMIT ?',
      [now, ...onlyEntries, limit * 3],
    );
    final seen = <String>{};
    final out = <DueItem>[];
    for (final row in rows) {
      final entryId = row['entry_id']! as String;
      if (!seen.add(entryId)) continue;
      final ctx = await _db.query('vocab_contexts', where: 'entry_id = ? AND sentence != ?', whereArgs: [entryId, ''], orderBy: 'created_at DESC', limit: 1);
      out.add(DueItem(entry: _entry(row), card: _card(row), context: ctx.isEmpty ? null : _context(ctx.first)));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Records one answer. Idempotent on [eventId]: replaying the same
  /// event (e.g. after the app was killed mid-write) changes nothing.
  Future<ReviewOutcome> recordReview({
    required String eventId,
    required String entryId,
    required CardType type,
    required Grade grade,
    required bool assisted,
    int? latencyMs,
  }) async {
    final now = _clock();
    return _db.transaction((txn) async {
      final entryRow = await txn.query('vocab_entries', where: 'id = ?', whereArgs: [entryId], limit: 1);
      if (entryRow.isEmpty) throw StateError('entry $entryId not found');
      final before = VocabStatus.parse(entryRow.first['status']! as String);
      final cardRow = await txn.query('review_cards', where: 'entry_id = ? AND card_type = ?', whereArgs: [entryId, type.name], limit: 1);
      if (cardRow.isEmpty) throw StateError('card $entryId/${type.name} not found');
      final card = _card(cardRow.first);

      final dup = await txn.query('review_events', where: 'id = ?', whereArgs: [eventId], limit: 1);
      if (dup.isNotEmpty) {
        return ReviewOutcome(state: card.state, before: before, after: before, duplicate: true);
      }

      final next = _scheduler.review(card.state, grade, assisted: assisted, now: now);
      await txn.insert('review_events', {
        'id': eventId,
        'entry_id': entryId,
        'card_type': type.name,
        'grade': grade.value,
        'assisted': assisted ? 1 : 0,
        'latency_ms': latencyMs,
        'reviewed_at': toMillis(now),
        'was_due': card.state.isDue(now) ? 1 : 0,
        'prev_interval': card.state.intervalDays,
        'new_interval': next.intervalDays,
      });
      await txn.update('review_cards', _cardValues(next), where: 'entry_id = ? AND card_type = ?', whereArgs: [entryId, type.name]);

      // Production is unlocked once the word is recognised without help.
      if (type == CardType.recognition && grade.isSuccess && !assisted) {
        await _insertCard(txn, entryId, CardType.production, now.add(const Duration(hours: 12)));
      }
      final after = await _refreshStatus(txn, entryId);
      return ReviewOutcome(state: next, before: before, after: after, duplicate: false);
    });
  }

  /// Recording usage in a conversation or writing task counts as
  /// production evidence without changing the schedule.
  Future<void> recordUsage(String entryId, SourceContext context) async {
    await _insertContext(_db, entryId, context, _clock());
  }

  Future<VocabStatus> _refreshStatus(DatabaseExecutor ex, String entryId) async {
    final entryRow = await ex.query('vocab_entries', columns: ['paused'], where: 'id = ?', whereArgs: [entryId]);
    if (entryRow.isEmpty) return VocabStatus.newlyEncountered;
    final cardRows = await ex.query('review_cards', where: 'entry_id = ?', whereArgs: [entryId]);
    final delayed = Sqflite.firstIntValue(await ex.rawQuery(
          'SELECT COUNT(*) FROM review_events WHERE entry_id = ? AND assisted = 0 AND grade > 0 AND prev_interval >= 21',
          [entryId],
        )) ??
        0;
    final status = deriveStatus(
      paused: entryRow.first['paused'] == 1,
      cards: cardRows.map((r) => _card(r).state).toList(),
      delayedUnaidedSuccesses: delayed,
    );
    await ex.update('vocab_entries', {'status': status.key, 'updated_at': toMillis(_clock())}, where: 'id = ?', whereArgs: [entryId]);
    return status;
  }

  // ----------------------------------------------------------- collections

  Future<List<CollectionInfo>> collections() async {
    final r = await _db.rawQuery(
      'SELECT c.id, c.name, COUNT(ci.entry_id) AS n FROM collections c '
      'LEFT JOIN collection_items ci ON ci.collection_id = c.id GROUP BY c.id ORDER BY c.created_at ASC',
    );
    return [for (final row in r) CollectionInfo(id: row['id']! as String, name: row['name']! as String, count: row['n']! as int)];
  }

  /// Lexeme ids of the dictionary entries in a collection.
  Future<List<String>> collectionLexemeIds(String collectionId) async {
    final r = await _db.rawQuery(
      'SELECT e.lexeme_id AS l FROM collection_items ci JOIN vocab_entries e ON e.id = ci.entry_id '
      'WHERE ci.collection_id = ? AND e.lexeme_id IS NOT NULL',
      [collectionId],
    );
    return [for (final row in r) row['l']! as String];
  }

  Future<String> createCollection(String name) async {
    final id = _ids();
    await _db.insert('collections', {'id': id, 'name': name.trim(), 'created_at': toMillis(_clock())});
    return id;
  }

  Future<void> renameCollection(String id, String name) =>
      _db.update('collections', {'name': name.trim()}, where: 'id = ?', whereArgs: [id]);

  Future<void> deleteCollection(String id) => _db.delete('collections', where: 'id = ?', whereArgs: [id]);

  Future<void> setInCollection(String collectionId, String entryId, bool member) async {
    if (member) {
      await _db.insert('collection_items', {'collection_id': collectionId, 'entry_id': entryId, 'added_at': toMillis(_clock())},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    } else {
      await _db.delete('collection_items', where: 'collection_id = ? AND entry_id = ?', whereArgs: [collectionId, entryId]);
    }
  }

  Future<Set<String>> collectionsOf(String entryId) async {
    final r = await _db.query('collection_items', columns: ['collection_id'], where: 'entry_id = ?', whereArgs: [entryId]);
    return {for (final row in r) row['collection_id']! as String};
  }

  // ---------------------------------------------------------------- stats

  /// Entries whose recognition is solid (interval ≥ 3 days) but whose
  /// production card failed last time: candidates for active practice.
  Future<List<VocabEntry>> productionGap({int limit = 10}) async {
    final r = await _db.rawQuery(
      'SELECT e.* FROM vocab_entries e '
      'JOIN review_cards rc ON rc.entry_id = e.id AND rc.card_type = ? AND rc.interval_days >= 3 '
      'JOIN review_cards pc ON pc.entry_id = e.id AND pc.card_type = ? AND pc.last_grade = 0 '
      'WHERE e.paused = 0 LIMIT ?',
      [CardType.recognition.name, CardType.production.name, limit],
    );
    return r.map(_entry).toList();
  }

  Future<int> unreviewedCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery("SELECT COUNT(*) FROM vocab_entries WHERE status = 'new' AND paused = 0")) ?? 0;

  // -------------------------------------------------------------- mapping

  static VocabEntry _entry(Map<String, Object?> r) => VocabEntry(
        id: r['id']! as String,
        lexemeId: r['lexeme_id'] as String?,
        headword: r['headword']! as String,
        lemma: r['lemma']! as String,
        kind: r['kind']! as String,
        article: r['article'] as String?,
        plural: r['plural'] as String?,
        meaningTr: r['meaning_tr']! as String,
        meaningEn: r['meaning_en'] as String?,
        note: r['note'] as String?,
        status: VocabStatus.parse(r['status']! as String),
        paused: r['paused'] == 1,
        createdAt: fromMillis(r['created_at']! as int),
        updatedAt: fromMillis(r['updated_at']! as int),
      );

  static SourceContext _context(Map<String, Object?> r) => SourceContext(
        type: SourceType.values.byName(r['source_type']! as String),
        sourceId: r['source_id']! as String,
        title: r['source_title'] as String?,
        sentence: r['sentence']! as String,
        sentenceTr: r['sentence_tr'] as String?,
        createdAt: fromMillis(r['created_at']! as int),
      );

  static ReviewCard _card(Map<String, Object?> r) => ReviewCard(
        entryId: r['entry_id']! as String,
        type: CardType.parse(r['card_type']! as String),
        state: CardState(
          ease: (r['ease']! as num).toDouble(),
          intervalDays: (r['interval_days']! as num).toDouble(),
          reps: r['reps']! as int,
          lapses: r['lapses']! as int,
          dueAt: fromMillis(r['due_at']! as int),
          lastReviewedAt: r['last_reviewed_at'] == null ? null : fromMillis(r['last_reviewed_at']! as int),
          lastUnaidedSuccessAt: r['last_unaided_success_at'] == null ? null : fromMillis(r['last_unaided_success_at']! as int),
          lastGrade: r['last_grade'] == null ? null : Grade.of(r['last_grade']! as int),
        ),
      );

  static Map<String, Object?> _cardValues(CardState s) => {
        'ease': s.ease,
        'interval_days': s.intervalDays,
        'reps': s.reps,
        'lapses': s.lapses,
        'due_at': toMillis(s.dueAt),
        'last_reviewed_at': s.lastReviewedAt == null ? null : toMillis(s.lastReviewedAt!),
        'last_unaided_success_at': s.lastUnaidedSuccessAt == null ? null : toMillis(s.lastUnaidedSuccessAt!),
        'last_grade': s.lastGrade?.value,
      };
}
