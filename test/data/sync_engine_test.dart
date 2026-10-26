import 'package:deutschap/core/db/app_database.dart';
import 'package:deutschap/core/db/kv_store.dart';
import 'package:deutschap/features/account/application/sync_engine.dart';
import 'package:deutschap/features/account/domain/account_backend.dart';
import 'package:deutschap/features/settings/data/data_repository.dart';
import 'package:deutschap/features/vocabulary/data/vocab_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';
import '../helpers/test_db.dart';

/// The server: one snapshot with a revision, like push_backup in SQL.
class FakeStore implements RemoteBackupStore {
  RemoteBackup? row;
  int pushes = 0;
  @override
  Future<RemoteBackup?> fetch() async => row;
  @override
  Future<int> push(String data, {required int schema, required String device, required int? expectedRevision}) async {
    if (expectedRevision != row?.revision) throw const RevisionConflict();
    pushes++;
    row = RemoteBackup(revision: (row?.revision ?? 0) + 1, data: data, device: device, updatedAt: DateTime(2026, 3, 2));
    return row!.revision;
  }
}

class Device {
  Device._(this.testDb, this.db, this.vocab, this.engine);
  final TestDb testDb;
  final AppDatabase db;
  final VocabRepository vocab;
  final SyncEngine engine;

  static Future<Device> create(FakeStore store, String name) async {
    final t = await TestDb.create();
    final db = await t.open();
    final clock = FakeClock(DateTime(2026, 3, 2, 9));
    final ids = SeqIds();
    return Device._(
      t,
      db,
      // Ids must be unique across devices, as UUIDs are in the app.
      VocabRepository(db.db, clock: clock.call, ids: () => '$name-${ids()}'),
      SyncEngine(data: DataRepository(db.db, clock: clock.call), kv: KvStore(db.db), store: store, userId: 'u1', device: name, clock: clock.call),
    );
  }

  Future<void> save(String lexemeId) => vocab.saveLexeme(loadTestContent().lexicon.byId(lexemeId)!);
  Future<bool> has(String lexemeId) async => await vocab.entryByLexeme(lexemeId) != null;

  Future<void> dispose() async {
    await db.close();
    await testDb.dispose();
  }
}

void main() {
  late FakeStore store;
  late Device phone;
  late Device laptop;

  setUp(() async {
    store = FakeStore();
    phone = await Device.create(store, 'phone');
    laptop = await Device.create(store, 'laptop');
  });
  tearDown(() async {
    await phone.dispose();
    await laptop.dispose();
  });

  test('first device uploads, a new empty device downloads', () async {
    await phone.save('tee');
    expect((await phone.engine.sync()).outcome, SyncOutcome.pushed);
    expect((await phone.engine.sync()).outcome, SyncOutcome.upToDate);
    expect((await laptop.engine.sync()).outcome, SyncOutcome.pulled);
    expect(await laptop.has('tee'), isTrue);
    expect((await laptop.engine.sync()).outcome, SyncOutcome.upToDate);
    expect(store.pushes, 1);
  });

  test('changes travel both ways when only one side changed', () async {
    await phone.save('tee');
    await phone.engine.sync();
    await laptop.engine.sync();

    await laptop.save('termin');
    expect((await laptop.engine.sync()).outcome, SyncOutcome.pushed);
    expect((await phone.engine.sync()).outcome, SyncOutcome.pulled);
    expect(await phone.has('termin'), isTrue);
  });

  test('both sides changed: nothing is overwritten until the learner chooses', () async {
    await phone.save('tee');
    await phone.engine.sync();
    await laptop.engine.sync();

    await phone.save('termin');
    await phone.engine.sync();
    await laptop.save('kaffee');

    final r = await laptop.engine.sync();
    expect(r.outcome, SyncOutcome.conflict);
    expect(r.remote, isNotNull);
    expect(await laptop.has('kaffee'), isTrue);
    expect(await laptop.has('termin'), isFalse);

    expect((await laptop.engine.sync(choice: SyncChoice.takeAccount)).outcome, SyncOutcome.pulled);
    expect(await laptop.has('termin'), isTrue);
    expect(await laptop.has('kaffee'), isFalse);
  });

  test('a device with its own data meeting an existing account asks first; keeping it uploads', () async {
    await phone.save('tee');
    await phone.engine.sync();
    await laptop.save('kaffee');
    expect((await laptop.engine.sync()).outcome, SyncOutcome.conflict);
    expect((await laptop.engine.sync(choice: SyncChoice.keepDevice)).outcome, SyncOutcome.pushed);
    expect((await phone.engine.sync()).outcome, SyncOutcome.pulled);
    expect(await phone.has('kaffee'), isTrue);
    expect(await phone.has('tee'), isFalse);
  });

  test('a push based on an old revision is refused', () async {
    await phone.save('tee');
    await phone.engine.sync();
    await laptop.engine.sync();
    await phone.save('termin');
    await phone.engine.sync();
    expect(() => store.push('{}', schema: 1, device: 'x', expectedRevision: 1), throwsA(isA<RevisionConflict>()));
  });

  test('another account on the same device starts fresh', () async {
    await phone.save('tee');
    await phone.engine.sync();
    final kv = KvStore(phone.db.db);
    final other = SyncEngine(
      data: DataRepository(phone.db.db, clock: () => DateTime(2026, 3, 3)),
      kv: kv,
      store: FakeStore(),
      userId: 'u2',
      device: 'phone',
      clock: () => DateTime(2026, 3, 3),
    );
    expect((await other.sync()).outcome, SyncOutcome.pushed);
    expect((await SyncEngine.meta(kv))!.userId, 'u2');
  });
}
