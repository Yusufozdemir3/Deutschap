import '../../../core/clock.dart';
import '../../../core/db/kv_store.dart';
import '../../../core/db/migrations.dart';
import '../../settings/data/data_repository.dart';
import '../domain/account_backend.dart';

enum SyncOutcome {
  /// Nothing changed on either side.
  upToDate,

  /// This device's data was uploaded.
  pushed,

  /// The account's data replaced this device's data.
  pulled,
}

class SyncResult {
  const SyncResult(this.outcome, {this.bothChanged = false, this.replacedDeviceData = false});
  final SyncOutcome outcome;

  /// The data on this device belonged to another account and was deleted
  /// before syncing.
  final bool replacedDeviceData;

  /// Both sides had changed since the last sync; the newer one was kept
  /// and the other side's changes were replaced.
  final bool bothChanged;
}

/// Snapshot sync (docs/adr/0005-accounts-and-sync.md): the whole learner
/// database travels as one backup. The engine remembers, per device, which
/// server revision it last saw and what the local data looked like then.
/// When only one side changed, that side wins. When both changed, the last
/// write wins: the side whose newest row is newer replaces the other.
class SyncEngine {
  SyncEngine({required DataRepository data, required KvStore kv, required RemoteBackupStore store, required this.userId, required this.device, required Clock clock})
      : _data = data,
        _kv = kv,
        _store = store,
        _clock = clock;

  final DataRepository _data;
  final KvStore _kv;
  final RemoteBackupStore _store;
  final String userId;
  final String device;
  final Clock _clock;

  /// Device-only (never in exports), see [DataRepository.isDeviceKey].
  static const metaKey = 'device.sync';

  static Future<SyncMeta?> meta(KvStore kv) async {
    final j = await kv.getJson(metaKey);
    return j.isEmpty ? null : SyncMeta.fromJson(j);
  }

  /// Device-only: the account this device's data was last synced with.
  /// Unlike [metaKey] it survives signing out, so a different account
  /// signing in is noticed.
  static const ownerKey = 'device.owner';

  static Future<void> forget(KvStore kv) => kv.set(metaKey, '{}');

  /// Signing in with another account than the one this device's data
  /// belongs to: the account's data is what the learner gets. The device's
  /// data is deleted first, never merged across accounts.
  Future<SyncResult> sync() async {
    final owner = await _kv.get(ownerKey);
    final foreign = owner != null && owner.isNotEmpty && owner != userId;
    if (foreign) await _data.deleteAll();
    final r = await _sync();
    return foreign ? SyncResult(r.outcome, bothChanged: r.bothChanged, replacedDeviceData: true) : r;
  }

  Future<SyncResult> _sync() async {
    final stored = await meta(_kv);
    // A different account signed in on this device starts from scratch.
    final m = stored?.userId == userId ? stored : null;
    final remote = await _store.fetch();
    final localHash = await _data.contentHash();
    final localChanged = m == null || m.localHash != localHash;

    if (remote == null) return _push(null, localHash);
    final remoteChanged = m == null || m.revision != remote.revision;

    if (!remoteChanged) return localChanged ? _push(remote.revision, localHash) : _ok(remote.revision, localHash, SyncOutcome.upToDate);
    if (!localChanged) return _pull(remote);
    // First sync on a device that has nothing yet: just take the account.
    if (m == null && !await _data.hasLearnerData()) return _pull(remote);

    // Both changed: last write wins. Both times come from the learner's
    // own rows (device clocks), not from when the snapshot reached the
    // server, so an upload delayed by being offline keeps its real age.
    // A tie keeps the account's copy.
    final local = await _data.lastChangedAt();
    final account = DataRepository.latestChange(DataRepository.inspect(remote.data).rows);
    final localNewer = local != null && (account == null || local.isAfter(account));
    return localNewer ? _push(remote.revision, localHash, bothChanged: true) : _pull(remote, bothChanged: true);
  }

  Future<SyncResult> _push(int? expected, String localHash, {bool bothChanged = false}) async {
    final json = await _data.exportJson();
    final revision = await _store.push(json, schema: schemaVersion, device: device, expectedRevision: expected);
    return _ok(revision, localHash, SyncOutcome.pushed, bothChanged: bothChanged);
  }

  Future<SyncResult> _pull(RemoteBackup remote, {bool bothChanged = false}) async {
    await _data.restore(DataRepository.inspect(remote.data));
    return _ok(remote.revision, await _data.contentHash(), SyncOutcome.pulled, bothChanged: bothChanged);
  }

  Future<SyncResult> _ok(int revision, String hash, SyncOutcome outcome, {bool bothChanged = false}) async {
    await _kv.set(ownerKey, userId);
    await _kv.setJson(metaKey, SyncMeta(userId: userId, revision: revision, localHash: hash, syncedAt: _clock()).toJson());
    return SyncResult(outcome, bothChanged: bothChanged);
  }
}

class SyncMeta {
  const SyncMeta({required this.userId, required this.revision, required this.localHash, required this.syncedAt});
  final String userId;
  final int revision;
  final String localHash;
  final DateTime syncedAt;

  Map<String, dynamic> toJson() => {'user': userId, 'rev': revision, 'hash': localHash, 'at': toMillis(syncedAt)};
  factory SyncMeta.fromJson(Map<String, dynamic> j) =>
      SyncMeta(userId: j['user'] as String, revision: j['rev'] as int, localHash: j['hash'] as String, syncedAt: fromMillis(j['at'] as int));
}
