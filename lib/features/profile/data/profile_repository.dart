import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../../core/clock.dart';
import '../domain/learner_profile.dart';

class ProfileRepository {
  ProfileRepository(this._db, {required Clock clock}) : _clock = clock;
  final Database _db;
  final Clock _clock;

  Future<LearnerProfile> load() async {
    final r = await _db.query('learner_profile', where: 'id = 1');
    if (r.isEmpty) return const LearnerProfile();
    return LearnerProfile.fromJson((jsonDecode(r.first['data']! as String) as Map).cast<String, dynamic>());
  }

  Future<void> save(LearnerProfile p) async {
    await _db.insert(
      'learner_profile',
      {'id': 1, 'data': jsonEncode(p.toJson()), 'updated_at': toMillis(_clock())},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
