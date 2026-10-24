import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// Web stores the database in IndexedDB through a wasm SQLite worker
/// (`web/sqlite3.wasm`, `web/sqflite_sw.js`).
DatabaseFactory platformDatabaseFactory() => databaseFactoryFfiWeb;

Future<String> platformDatabasePath(String name) async => name;
