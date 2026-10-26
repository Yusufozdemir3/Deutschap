/// The seam between the app and the account server. The app works fully
/// without it; [NoAccountBackend] is used when no server is configured.
abstract class AccountBackend {
  bool get configured;

  AccountUser? get user;
  Stream<AccountUser?> get userChanges;

  /// Sends a six-digit sign-in code by e-mail. Creates the account on first use.
  Future<void> sendCode(String email);

  /// Signs in with the code from the e-mail.
  Future<void> verifyCode(String email, String code);

  /// Ends the session on this device. Local data stays.
  Future<void> signOut();

  /// Deletes the account and everything stored with it on the server.
  Future<void> deleteAccount();

  RemoteBackupStore get backups;
}

class AccountUser {
  const AccountUser({required this.id, required this.email});
  final String id;
  final String? email;
}

/// The learner's data on the server: one snapshot per account, versioned
/// by a revision number so two devices cannot silently overwrite each other.
abstract class RemoteBackupStore {
  Future<RemoteBackup?> fetch();

  /// Stores [data] if the server copy is still at [expectedRevision]
  /// (null: there is none yet). Returns the new revision, or throws
  /// [RevisionConflict] when another device pushed in between.
  Future<int> push(String data, {required int schema, required String device, required int? expectedRevision});
}

class RemoteBackup {
  const RemoteBackup({required this.revision, required this.data, required this.updatedAt, this.device});
  final int revision;
  final String data;
  final DateTime updatedAt;
  final String? device;
}

class RevisionConflict implements Exception {
  const RevisionConflict();
}

/// A failure the learner should see in plain words (no network, wrong code).
class AccountException implements Exception {
  const AccountException(this.message);
  final String message;
  @override
  String toString() => message;
}

class NoAccountBackend implements AccountBackend {
  const NoAccountBackend();
  static const _msg = AccountException('Bu sürümde hesap sunucusu ayarlı değil.');
  @override
  bool get configured => false;
  @override
  AccountUser? get user => null;
  @override
  Stream<AccountUser?> get userChanges => const Stream.empty();
  @override
  Future<void> sendCode(String email) => Future.error(_msg);
  @override
  Future<void> verifyCode(String email, String code) => Future.error(_msg);
  @override
  Future<void> signOut() async {}
  @override
  Future<void> deleteAccount() => Future.error(_msg);
  @override
  RemoteBackupStore get backups => throw _msg;
}
