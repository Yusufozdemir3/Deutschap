import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Small key-value store for UI conveniences (e.g. which discover cards
/// were seen). Learner data with structure belongs in its own table.
class KvStore {
  KvStore(this._db);
  final Database _db;

  Future<String?> get(String key) async {
    final r = await _db.query('kv', where: 'key = ?', whereArgs: [key]);
    return r.isEmpty ? null : r.first['value']! as String;
  }

  Future<void> set(String key, String value) =>
      _db.insert('kv', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<Map<String, dynamic>> getJson(String key) async {
    final v = await get(key);
    if (v == null) return {};
    try {
      return (jsonDecode(v) as Map).cast<String, dynamic>();
    } on FormatException {
      return {};
    }
  }

  Future<void> setJson(String key, Map<String, dynamic> value) => set(key, jsonEncode(value));
}
