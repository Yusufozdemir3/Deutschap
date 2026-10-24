import 'package:sqflite/sqflite.dart';

import '../../../core/clock.dart';

enum ReadingSource { builtin, pasted }

class ReadingDoc {
  const ReadingDoc({
    required this.id,
    required this.title,
    required this.body,
    required this.source,
    required this.position,
    required this.updatedAt,
    this.builtinId,
  });
  final String id;
  final String title;
  final String body;
  final ReadingSource source;

  /// Paragraph index the learner last reached.
  final int position;
  final String? builtinId;
  final DateTime updatedAt;
}

/// Reading documents stay on the device. Pasted texts are never uploaded.
class ReadingRepository {
  ReadingRepository(this._db, {required Clock clock, required IdGenerator ids})
      : _clock = clock,
        _ids = ids;
  final Database _db;
  final Clock _clock;
  final IdGenerator _ids;

  static const maxPastedChars = 20000;

  Future<List<ReadingDoc>> pastedDocs() async {
    final r = await _db.query('reading_docs', where: 'source = ?', whereArgs: [ReadingSource.pasted.name], orderBy: 'updated_at DESC');
    return r.map(_doc).toList();
  }

  Future<ReadingDoc?> doc(String id) async {
    final r = await _db.query('reading_docs', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : _doc(r.first);
  }

  /// Built-in texts get a row the first time they are opened so the
  /// reading position can be stored.
  Future<ReadingDoc> openBuiltin(String builtinId, String title, String body) async {
    final r = await _db.query('reading_docs', where: 'builtin_id = ?', whereArgs: [builtinId]);
    if (r.isNotEmpty) return _doc(r.first);
    final now = toMillis(_clock());
    final id = 'builtin:$builtinId';
    await _db.insert(
      'reading_docs',
      {'id': id, 'title': title, 'body': body, 'source': ReadingSource.builtin.name, 'builtin_id': builtinId, 'position': 0, 'created_at': now, 'updated_at': now},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    return (await doc(id))!;
  }

  Future<Map<String, int>> builtinPositions() async {
    final r = await _db.query('reading_docs', columns: ['builtin_id', 'position'], where: 'builtin_id IS NOT NULL');
    return {for (final row in r) row['builtin_id']! as String: row['position']! as int};
  }

  Future<String> addPasted(String title, String body) async {
    final text = body.trim();
    if (text.isEmpty) throw ArgumentError('empty text');
    if (text.length > maxPastedChars) throw ArgumentError('text too long');
    final id = _ids();
    final now = toMillis(_clock());
    await _db.insert('reading_docs', {
      'id': id,
      'title': title.trim().isEmpty ? _titleFrom(text) : title.trim(),
      'body': text,
      'source': ReadingSource.pasted.name,
      'position': 0,
      'created_at': now,
      'updated_at': now,
    });
    return id;
  }

  Future<void> savePosition(String id, int paragraph) =>
      _db.update('reading_docs', {'position': paragraph, 'updated_at': toMillis(_clock())}, where: 'id = ?', whereArgs: [id]);

  /// Deletes the document. Words saved from it stay in the library with
  /// their sentence; the link back to the document is no longer offered.
  Future<void> delete(String id) => _db.delete('reading_docs', where: 'id = ?', whereArgs: [id]);

  static String _titleFrom(String text) {
    final first = text.split(RegExp(r'[\n.!?]')).first.trim();
    return first.length <= 40 ? first : '${first.substring(0, 40)}…';
  }

  static ReadingDoc _doc(Map<String, Object?> r) => ReadingDoc(
        id: r['id']! as String,
        title: r['title']! as String,
        body: r['body']! as String,
        source: ReadingSource.values.byName(r['source']! as String),
        position: r['position']! as int,
        builtinId: r['builtin_id'] as String?,
        updatedAt: fromMillis(r['updated_at']! as int),
      );
}
