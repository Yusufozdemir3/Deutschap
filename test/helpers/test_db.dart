import 'dart:io';

import 'package:deutschap/core/db/app_database.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A fresh on-disk database in a temp directory, so tests can also
/// simulate an app restart by closing and reopening the same file.
class TestDb {
  TestDb._(this.dir);
  final Directory dir;
  String get path => p.join(dir.path, 'test.db');

  static Future<TestDb> create() async {
    sqfliteFfiInit();
    return TestDb._(await Directory.systemTemp.createTemp('deutschap_test_'));
  }

  Future<AppDatabase> open() => AppDatabase.open(factory: databaseFactoryFfiNoIsolate, path: path);

  Future<void> dispose() async {
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  }
}

/// Deterministic clock and ids for repository tests.
class FakeClock {
  FakeClock(this.now);
  DateTime now;
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

class SeqIds {
  var _n = 0;
  String call() => 'id-${_n++}';
}
