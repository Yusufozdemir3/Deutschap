import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as mobile;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Android/iOS use the platform sqflite plugin; desktop uses FFI.
DatabaseFactory platformDatabaseFactory() {
  if (Platform.isAndroid || Platform.isIOS) return mobile.databaseFactory;
  sqfliteFfiInit();
  return databaseFactoryFfi;
}

Future<String> platformDatabasePath(String name) async {
  if (Platform.isAndroid || Platform.isIOS) {
    return p.join(await mobile.getDatabasesPath(), name);
  }
  final dir = await getApplicationSupportDirectory();
  await dir.create(recursive: true);
  return p.join(dir.path, name);
}
