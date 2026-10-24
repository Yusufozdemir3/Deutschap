import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/clock.dart';
import '../../../core/db/app_database.dart';

/// Export and deletion of everything the learner created.
class DataRepository {
  DataRepository(this._db, {required Clock clock}) : _clock = clock;
  final Database _db;
  final Clock _clock;

  static const exportFormat = 'deutschap-export';
  static const exportVersion = 1;

  /// All learner tables as JSON. Content shipped with the app is not
  /// included; it can be re-downloaded with the app.
  Future<String> exportJson() async {
    final tables = <String, Object?>{};
    for (final t in AppDatabase.learnerTables.reversed) {
      tables[t] = await _db.query(t);
    }
    return const JsonEncoder.withIndent('  ').convert({
      'format': exportFormat,
      'version': exportVersion,
      'exported_at': _clock().toUtc().toIso8601String(),
      'tables': tables,
    });
  }

  /// Vocabulary only, as tab-separated text that other tools can import.
  Future<String> exportVocabularyTsv() async {
    final r = await _db.query('vocab_entries', orderBy: 'created_at ASC');
    final b = StringBuffer('german\tplural\tturkish\tnote\tstatus\n');
    String clean(Object? v) => (v as String? ?? '').replaceAll(RegExp(r'[\t\n]'), ' ');
    for (final row in r) {
      b.writeln([row['headword'], row['plural'], row['meaning_tr'], row['note'], row['status']].map(clean).join('\t'));
    }
    return b.toString();
  }

  /// Irreversibly removes all learner data on this device.
  Future<void> deleteAll() async {
    await _db.transaction((txn) async {
      for (final t in AppDatabase.learnerTables) {
        await txn.delete(t);
      }
    });
  }

  /// Resets the personalisation signals (recurring errors, activity
  /// history) while keeping vocabulary and progress.
  Future<void> resetLearningSignals() async {
    await _db.transaction((txn) async {
      await txn.delete('conversation_sessions');
      await txn.delete('exercise_attempts');
    });
  }
}
