import 'package:sqflite/sqflite.dart';

import 'db_factory.dart';
import 'migrations.dart';

/// Thin owner of the SQLite connection. Feature repositories receive it
/// and issue their own SQL; no business logic lives here.
class AppDatabase {
  AppDatabase._(this.db);

  final Database db;

  static const fileName = 'deutschap.db';

  /// Every learner-data table, in an order that respects foreign keys
  /// for deletion (children first).
  static const learnerTables = [
    'collection_items',
    'collections',
    'review_events',
    'review_cards',
    'vocab_contexts',
    'vocab_entries',
    'lesson_progress',
    'story_progress',
    'reading_docs',
    'exercise_attempts',
    'conversation_sessions',
    'activity_log',
    'learner_profile',
    'kv',
  ];

  static Future<AppDatabase> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? platformDatabaseFactory();
    final dbPath = path ?? await platformDatabasePath(fileName);
    final db = await f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) => _migrate(db, 0, version),
        onUpgrade: _migrate,
      ),
    );
    return AppDatabase._(db);
  }

  static Future<void> _migrate(Database db, int from, int to) async {
    await db.transaction((txn) async {
      for (var v = from; v < to; v++) {
        await migrations[v](txn);
      }
    });
  }

  Future<void> close() => db.close();
}
