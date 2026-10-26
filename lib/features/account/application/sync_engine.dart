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

  /// Both sides changed since the last sync; the learner has to choose.
  conflict,
}

/// How the learner resolved a [SyncOutcome.conflict].
enum SyncChoice { keepDevice, takeAccount }

class SyncResult {
  const SyncResult(this.outcome, {this.remote});
  final SyncOutcome outcome;

  /// The account's copy, for showing what a conflict is about.
  final RemoteBackup? remote;
}

/// Snapshot sync (docs/adr/0005-accounts-and-sync.md): the whole learner
/// database travels as one backup. The engine remembers, per device, which
/// server revision it last saw and what the local data looked like then,
/// which is enough to tell "only here changed", "only there changed" and
/// "both changed" apart. Nothing is ever overwritten without one side
/// being unchanged or the learner choosing.
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

  /// Device-only (never in backups), see [DataRepository.isDeviceKey].
  static const metaKey = 'device.sync';

  static Future<SyncMeta?> meta(KvStore kv) async {
    final j = await kv.getJson(metaKey);
    return j.isEmpty ? null : SyncMeta.fromJson(j);
  }

  static Future<void> forget(KvStore kv) => kv.set(metaKey, '{}');

  Future<SyncResult> sync({SyncChoice? choice}) async {
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

    return switch (choice) {
      SyncChoice.keepDevice => _push(remote.revision, localHash),
      SyncChoice.takeAccount => _pull(remote),
      null => SyncResult(SyncOutcome.conflict, remote: remote),
    };
  }

  Future<SyncResult> _push(int? expected, String localHash) async {
    final json = await _data.exportJson();
    final revision = await _store.push(json, schema: schemaVersion, device: device, expectedRevision: expected);
    return _ok(revision, localHash, SyncOutcome.pushed);
  }

  Future<SyncResult> _pull(RemoteBackup remote) async {
    await _data.restore(DataRepository.inspect(remote.data));
    return _ok(remote.revision, await _data.contentHash(), SyncOutcome.pulled, remote: remote);
  }

  Future<SyncResult> _ok(int revision, String hash, SyncOutcome outcome, {RemoteBackup? remote}) async {
    await _kv.setJson(metaKey, SyncMeta(userId: userId, revision: revision, localHash: hash, syncedAt: _clock()).toJson());
    return SyncResult(outcome, remote: remote);
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
