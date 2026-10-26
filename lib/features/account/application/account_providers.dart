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
  const SyncStatus({this.busy = false, this.meta, this.last, this.conflict, this.error});
  final bool busy;
  final SyncMeta? meta;
  final SyncOutcome? last;

  /// The account's copy while a conflict waits for the learner.
  final RemoteBackup? conflict;
  final String? error;
}

/// Runs [SyncEngine] for the signed-in learner: on demand, when the app
/// starts or comes back, and shortly after local changes.
class SyncController extends Notifier<SyncStatus> {
  Timer? _debounce;

  @override
  SyncStatus build() {
    ref.onDispose(() => _debounce?.cancel());
    unawaited(_loadMeta());
    return const SyncStatus();
  }

  Future<void> _loadMeta() async {
    final m = await SyncEngine.meta(ref.read(kvStoreProvider));
    state = SyncStatus(meta: m, last: state.last, conflict: state.conflict, error: state.error);
  }

  AccountUser? get _user => ref.read(accountUserProvider).valueOrNull ?? ref.read(accountBackendProvider).user;

  /// Debounced sync after the learner changed something.
  void schedule() {
    if (_user == null) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 20), () => run(quiet: true));
  }

  Future<SyncOutcome?> run({SyncChoice? choice, bool quiet = false}) async {
    final user = _user;
    if (user == null || state.busy) return null;
    // A pending conflict is only resolved by the learner, never in the background.
    if (quiet && state.conflict != null) return SyncOutcome.conflict;
    state = SyncStatus(busy: true, meta: state.meta, last: state.last, conflict: state.conflict);
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
        r = await engine.sync(choice: choice);
      } on RevisionConflict {
        // Another device pushed between our read and write: look again.
        r = await engine.sync(choice: choice);
      }
      if (r.outcome == SyncOutcome.pulled) {
        ref.bumpData();
        await ref.read(profileProvider.notifier).reload();
      }
      state = SyncStatus(
        meta: await SyncEngine.meta(ref.read(kvStoreProvider)),
        last: r.outcome,
        conflict: r.outcome == SyncOutcome.conflict ? r.remote : null,
      );
      return r.outcome;
    } catch (e) {
      state = SyncStatus(meta: state.meta, last: state.last, conflict: state.conflict, error: quiet ? null : e.toString());
      return null;
    }
  }

  Future<void> signOut() async {
    _debounce?.cancel();
    await ref.read(accountBackendProvider).signOut();
    await SyncEngine.forget(ref.read(kvStoreProvider));
    state = const SyncStatus();
  }

  Future<void> deleteAccount() async {
    _debounce?.cancel();
    await ref.read(accountBackendProvider).deleteAccount();
    await SyncEngine.forget(ref.read(kvStoreProvider));
    state = const SyncStatus();
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(SyncController.new);
