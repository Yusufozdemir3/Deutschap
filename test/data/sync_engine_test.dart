import 'package:deutschap/core/db/app_database.dart';
import 'package:deutschap/core/db/kv_store.dart';
import 'package:deutschap/features/account/application/account_providers.dart';
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
  Device._(this.testDb, this.db, this.clock, this.vocab, this.engine);
  final TestDb testDb;
  final AppDatabase db;
  final FakeClock clock;
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
      clock,
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
    final r = await laptop.engine.sync();
    expect(r.outcome, SyncOutcome.pushed);
    expect(r.bothChanged, isFalse);
    expect((await phone.engine.sync()).outcome, SyncOutcome.pulled);
    expect(await phone.has('termin'), isTrue);
  });

  test('both sides changed: the later write wins, whichever device syncs first', () async {
    await phone.save('tee');
    await phone.engine.sync();
    await laptop.engine.sync();

    // The laptop writes later, but the phone syncs first.
    phone.clock.advance(const Duration(minutes: 5));
    await phone.save('termin');
    await phone.engine.sync();
    laptop.clock.advance(const Duration(minutes: 10));
    await laptop.save('kaffee');

    final r = await laptop.engine.sync();
    expect(r.outcome, SyncOutcome.pushed);
    expect(r.bothChanged, isTrue);
    expect(await laptop.has('kaffee'), isTrue);
    expect(await laptop.has('termin'), isFalse);

    expect((await phone.engine.sync()).outcome, SyncOutcome.pulled);
    expect(await phone.has('kaffee'), isTrue);
    expect(await phone.has('termin'), isFalse);
  });

  test('both sides changed: an older local write gives way to the account', () async {
    await phone.save('tee');
    await phone.engine.sync();
    await laptop.engine.sync();

    laptop.clock.advance(const Duration(minutes: 5));
    await laptop.save('kaffee');
    phone.clock.advance(const Duration(minutes: 10));
    await phone.save('termin');
    await phone.engine.sync();

    final r = await laptop.engine.sync();
    expect(r.outcome, SyncOutcome.pulled);
    expect(r.bothChanged, isTrue);
    expect(await laptop.has('termin'), isTrue);
    expect(await laptop.has('kaffee'), isFalse);
  });

  test('a device with its own data meeting an existing account: the newer data wins', () async {
    await phone.save('tee');
    await phone.engine.sync();
    laptop.clock.advance(const Duration(hours: 1));
    await laptop.save('kaffee');

    expect((await laptop.engine.sync()).outcome, SyncOutcome.pushed);
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

  test('latest change ignores planned review times', () {
    final t = DateTime(2026, 3, 2, 9).millisecondsSinceEpoch;
    expect(
      DataRepository.latestChange({
        'review_cards': [
          {'due_at': t + 999999, 'last_reviewed_at': t},
        ],
      }),
      DateTime.fromMillisecondsSinceEpoch(t),
    );
    expect(DataRepository.latestChange({'kv': []}), isNull);
  });

  SyncEngine asUser(Device d, String id, FakeStore store) => SyncEngine(
        data: DataRepository(d.db.db, clock: () => DateTime(2026, 3, 3)),
        kv: KvStore(d.db.db),
        store: store,
        userId: id,
        device: 'phone',
        clock: () => DateTime(2026, 3, 3),
      );

  test('another account signing in gets its own data; the device data is deleted, not merged', () async {
    await phone.save('tee');
    await phone.engine.sync();
    final other = FakeStore();
    final second = await Device.create(other, 'second');
    await second.save('kaffee');
    await asUser(second, 'u2', other).sync();

    final r = await asUser(phone, 'u2', other).sync();
    expect(r.outcome, SyncOutcome.pulled);
    expect(r.replacedDeviceData, isTrue);
    expect(await phone.has('tee'), isFalse);
    expect(await phone.has('kaffee'), isTrue);
    expect((await SyncEngine.meta(KvStore(phone.db.db)))!.userId, 'u2');
    await second.dispose();
  });

  test('a new account with nothing on the server starts empty, never with the other account data', () async {
    await phone.save('tee');
    await phone.engine.sync();
    final other = FakeStore();
    final r = await asUser(phone, 'u2', other).sync();
    expect(r.replacedDeviceData, isTrue);
    expect(await phone.has('tee'), isFalse);
    expect(DataRepository.inspect(other.row!.data).rows['vocab_entries'], isEmpty);
  });

  test('the first account on a device that had data before accounts keeps it', () async {
    await phone.save('tee');
    final other = FakeStore();
    final r = await asUser(phone, 'u1', other).sync();
    expect(r.outcome, SyncOutcome.pushed);
    expect(r.replacedDeviceData, isFalse);
    expect(await phone.has('tee'), isTrue);
  });

  test('the same account signing in again after signing out keeps its data', () async {
    await phone.save('tee');
    await phone.engine.sync();
    await SyncEngine.forget(KvStore(phone.db.db));
    final r = await phone.engine.sync();
    expect(r.replacedDeviceData, isFalse);
    expect(await phone.has('tee'), isTrue);
  });

  test('the app is gated on an account only when a server is configured', () {
    const user = AccountUser(id: 'u1', email: 'a@b.c');
    AccountGate gate({bool configured = true, AccountUser? u = user, String? owner = '', bool settled = false}) =>
        accountGateFor(configured: configured, user: u, deviceOwner: owner, settled: settled);
    expect(gate(configured: false, u: null), AccountGate.open);
    expect(gate(u: null, owner: 'u1', settled: true), AccountGate.needsSignIn);
    expect(gate(), AccountGate.preparing);
    expect(gate(owner: 'u2'), AccountGate.preparing);
    expect(gate(owner: 'u1'), AccountGate.open);
    expect(gate(settled: true), AccountGate.open);
  });
}
