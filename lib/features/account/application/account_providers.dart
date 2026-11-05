import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

import '../../../app/providers.dart';
import '../../../core/clock.dart';
import '../data/supabase_backend.dart';
import '../domain/account_backend.dart';
import 'sync_engine.dart';

final accountBackendProvider = Provider<AccountBackend>(
  (ref) => BackendConfig.ready ? SupabaseAccountBackend(Supabase.instance.client) : const NoAccountBackend(),
);

final accountUserProvider = StreamProvider<AccountUser?>((ref) async* {
  final backend = ref.watch(accountBackendProvider);
  yield backend.user;
  yield* backend.userChanges;
});

String get _deviceName => kIsWeb ? 'web' : defaultTargetPlatform.name;

class SyncStatus {
  const SyncStatus({this.busy = false, this.meta, this.last, this.error, this.owner, this.settled = false, this.sessionExpired = false});
  final bool busy;
  final SyncMeta? meta;
  final SyncResult? last;
  final String? error;

  /// The account this device's data was last synced with.
  final String? owner;

  /// A sync (or its fallback timeout) finished since signing in.
  final bool settled;

  /// The session ended without the learner signing out (e.g. it expired).
  final bool sessionExpired;

  SyncStatus copyWith({bool? busy, SyncMeta? meta, SyncResult? last, String? error, bool clearError = false, String? owner, bool? settled, bool? sessionExpired}) => SyncStatus(
        busy: busy ?? this.busy,
        meta: meta ?? this.meta,
        last: last ?? this.last,
        error: clearError ? null : (error ?? this.error),
        owner: owner ?? this.owner,
        settled: settled ?? this.settled,
        sessionExpired: sessionExpired ?? this.sessionExpired,
      );
}

/// Runs [SyncEngine] for the signed-in learner: on demand, when the app
/// starts or comes back, and shortly after local changes.
class SyncController extends Notifier<SyncStatus> {
  Timer? _debounce;
  bool _signingOut = false;

  @override
  SyncStatus build() {
    ref.onDispose(() => _debounce?.cancel());
    ref.listen(accountUserProvider, (prev, next) {
      final was = prev?.valueOrNull, now = next.valueOrNull;
      if (was != null && now == null && !_signingOut) {
        _debounce?.cancel();
        state = state.copyWith(sessionExpired: true);
      } else if (now != null) {
        state = state.copyWith(sessionExpired: false);
        _settleSoon();
      }
    });
    unawaited(_loadMeta());
    if (_user != null) _settleSoon();
    return const SyncStatus();
  }

  Future<void> _loadMeta() async {
    final kv = ref.read(kvStoreProvider);
    final meta = await SyncEngine.meta(kv);
    final owner = await kv.get(SyncEngine.ownerKey) ?? '';
    state = state.copyWith(meta: meta, owner: owner);
  }

  /// If the first sync after sign-in hangs (no network), let the learner
  /// in anyway with what is on the device.
  void _settleSoon() {
    Timer(const Duration(seconds: 8), () {
      if (_user != null && !state.settled) state = state.copyWith(settled: true);
    });
  }

  AccountUser? get _user => ref.read(accountUserProvider).valueOrNull ?? ref.read(accountBackendProvider).user;

  /// Debounced sync after the learner changed something.
  void schedule() {
    if (_user == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 20), () => run(quiet: true));
  }

  Future<SyncResult?> run({bool quiet = false}) async {
    final user = _user;
    if (user == null || state.busy) return null;
    state = state.copyWith(busy: true, clearError: true);
    final engine = SyncEngine(
      data: ref.read(dataRepositoryProvider),
      kv: ref.read(kvStoreProvider),
      store: ref.read(accountBackendProvider).backups,
      userId: user.id,
      device: _deviceName,
      clock: ref.read(clockProvider),
    );
    try {
      SyncResult r;
      try {
        r = await engine.sync();
      } on RevisionConflict {
        // Another device pushed between our read and write: look again.
        r = await engine.sync();
      }
      if (r.outcome == SyncOutcome.pulled || r.replacedDeviceData) {
        ref.bumpData();
        await ref.read(profileProvider.notifier).reload();
      }
      final kv = ref.read(kvStoreProvider);
      state = state.copyWith(busy: false, meta: await SyncEngine.meta(kv), owner: await kv.get(SyncEngine.ownerKey) ?? '', last: r, settled: true);
      return r;
    } catch (e) {
      state = state.copyWith(busy: false, error: e.toString(), settled: true);
      return null;
    }
  }

  Future<void> signOut() async {
    _debounce?.cancel();
    _signingOut = true;
    try {
      await ref.read(accountBackendProvider).signOut();
    } finally {
      // The signed-out event reaches accountUserProvider a moment later.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      _signingOut = false;
    }
    await SyncEngine.forget(ref.read(kvStoreProvider));
    state = SyncStatus(owner: state.owner);
  }

  Future<void> deleteAccount() async {
    _debounce?.cancel();
    _signingOut = true;
    try {
      await ref.read(accountBackendProvider).deleteAccount();
    } finally {
      // The signed-out event reaches accountUserProvider a moment later.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      _signingOut = false;
    }
    await SyncEngine.forget(ref.read(kvStoreProvider));
    // The account is gone and so is its data on this device.
    await ref.read(dataRepositoryProvider).deleteAll();
    await ref.read(kvStoreProvider).set(SyncEngine.ownerKey, '');
    ref.bumpData();
    await ref.read(profileProvider.notifier).reload();
    state = const SyncStatus(owner: '');
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);

/// Where the app stands with the account. An account is required when the
/// build has a server; without one (no keys) the app runs on the device alone.
enum AccountGate {
  /// Use the app.
  open,

  /// Show the sign-in screen.
  needsSignIn,

  /// Signed in, waiting for the first sync that decides which data this
  /// device shows.
  preparing,
}

/// [deviceOwner] is the account the device's data was last synced with
/// ('' none yet, null not read yet: the app opens at its deep link and the
/// gate closes a moment later if the account turns out to be a new one).
AccountGate accountGateFor({required bool configured, required AccountUser? user, required String? deviceOwner, required bool settled}) {
  if (!configured) return AccountGate.open;
  if (user == null) return AccountGate.needsSignIn;
  return settled || deviceOwner == null || deviceOwner == user.id ? AccountGate.open : AccountGate.preparing;
}

final accountGateProvider = Provider<AccountGate>((ref) {
  final backend = ref.watch(accountBackendProvider);
  final user = ref.watch(accountUserProvider).valueOrNull ?? backend.user;
  final s = ref.watch(syncControllerProvider);
  return accountGateFor(configured: backend.configured, user: user, deviceOwner: s.owner, settled: s.settled);
});
