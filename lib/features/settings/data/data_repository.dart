import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/clock.dart';
import '../../../core/db/app_database.dart';
import '../../../core/db/migrations.dart';

/// Export and deletion of everything the learner created.
class DataRepository {
  DataRepository(this._db, {required Clock clock}) : _clock = clock;
  final Database _db;
  final Clock _clock;

  static const exportFormat = 'deutschap-export';
  static const exportVersion = 1;

  /// `kv` keys that describe this device rather than the learner (downloaded
  /// content, sync bookkeeping). They are left out of backups and survive a
  /// restore.
  static bool isDeviceKey(String key) => key == 'content_overrides' || key.startsWith('device.');

  /// All learner tables as JSON. Content shipped with the app is not
  /// included; it can be re-downloaded with the app.
  Future<String> exportJson() async => const JsonEncoder.withIndent('  ').convert({
        'format': exportFormat,
        'version': exportVersion,
        'schema': schemaVersion,
        'exported_at': _clock().toUtc().toIso8601String(),
        'tables': await _tables(),
      });

  Future<Map<String, Object?>> _tables() async {
    final tables = <String, Object?>{};
    for (final t in AppDatabase.learnerTables.reversed) {
      // A stable order keeps the hash below independent of insert order.
      final rows = await _db.query(t, orderBy: 'rowid');
      tables[t] = t == 'kv' ? rows.where((r) => !isDeviceKey(r['key']! as String)).toList() : rows;
    }
    return tables;
  }

  /// Fingerprint of the learner data (not the export time), used by sync
  /// to tell whether anything changed since the last sync. FNV-1a, 32 bit:
  /// a change detector, not a security measure.
  Future<String> contentHash() async {
    var h = 0x811c9dc5;
    for (final c in jsonEncode(await _tables()).codeUnits) {
      h ^= c;
      // h * 0x01000193 without exceeding 2^53 (same result on web and VM).
      h = (h * 0x193 + ((h << 24) & 0xffffffff)) & 0xffffffff;
    }
    return h.toRadixString(16);
  }

  /// True when the learner has not created anything worth keeping yet.
  Future<bool> hasLearnerData() async {
    for (final t in const ['vocab_entries', 'lesson_progress', 'story_progress', 'review_events', 'reading_docs']) {
      if ((Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM $t')) ?? 0) > 0) return true;
    }
    return false;
  }

  /// Checks a backup without touching the database. Throws
  /// [BackupFormatException] with a learner-facing message when the file
  /// is not a Deutschap backup or comes from a newer app version.
  static BackupSummary inspect(String json) {
    final Object? root;
    try {
      root = jsonDecode(json);
    } on FormatException {
      throw const BackupFormatException('Dosya okunamadı: geçerli bir JSON değil.');
    }
    if (root is! Map || root['format'] != exportFormat) {
      throw const BackupFormatException('Bu bir Deutschap yedeği değil.');
    }
    final version = root['version'];
    final schema = root['schema'] ?? 1;
    if (version is! int || version > exportVersion || schema is! int || schema > schemaVersion) {
      throw const BackupFormatException('Bu yedek uygulamanın daha yeni bir sürümüyle alınmış. Önce uygulamayı güncelle.');
    }
    final tables = root['tables'];
    if (tables is! Map) throw const BackupFormatException('Yedekte tablo yok.');
    final rows = <String, List<Map<String, Object?>>>{};
    for (final e in tables.entries) {
      if (!AppDatabase.learnerTables.contains(e.key)) throw BackupFormatException('Bilinmeyen tablo: ${e.key}');
      final list = e.value;
      if (list is! List || list.any((r) => r is! Map)) throw BackupFormatException('Bozuk tablo: ${e.key}');
      rows[e.key as String] = [for (final r in list) (r as Map).cast<String, Object?>()];
    }
    return BackupSummary(
      exportedAt: DateTime.tryParse(root['exported_at'] as String? ?? '')?.toLocal(),
      rows: rows,
    );
  }

  /// Replaces all learner data with the backup, in one transaction: on any
  /// error nothing changes.
  Future<void> restore(BackupSummary backup) async {
    try {
      await _db.transaction((txn) async {
        for (final t in AppDatabase.learnerTables) {
          if (t == 'kv') {
            final keys = [for (final r in await txn.query('kv')) r['key']! as String];
            for (final k in keys.where((k) => !isDeviceKey(k))) {
              await txn.delete('kv', where: 'key = ?', whereArgs: [k]);
            }
          } else {
            await txn.delete(t);
          }
        }
        for (final t in AppDatabase.learnerTables.reversed) {
          for (final row in backup.rows[t] ?? const <Map<String, Object?>>[]) {
            if (t == 'kv' && isDeviceKey(row['key'] as String? ?? '')) continue;
            await txn.insert(t, row);
          }
        }
      });
    } on DatabaseException catch (e) {
      throw BackupFormatException('Yedek geri yüklenemedi; verilerin değişmedi. ($e)');
    }
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

class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// A parsed backup, shown to the learner before it replaces their data.
class BackupSummary {
  const BackupSummary({required this.exportedAt, required this.rows});
  final DateTime? exportedAt;
  final Map<String, List<Map<String, Object?>>> rows;

  int count(String table) => rows[table]?.length ?? 0;
  int get words => count('vocab_entries');
  int get lessons => count('lesson_progress');
  int get episodes => count('story_progress');
  int get reviews => count('review_events');
}
