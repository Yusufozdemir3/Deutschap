import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/account_backend.dart';

/// Build-time configuration, e.g.
/// `flutter run --dart-define=SUPABASE_URL=https://….supabase.co --dart-define=SUPABASE_PUBLISHABLE_KEY=…`.
/// The publishable key is meant to ship in clients; row-level security on
/// the server (supabase/migrations) decides what it may read and write.
class BackendConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static bool get configured => url.isNotEmpty && publishableKey.isNotEmpty;

  /// True once [initialize] succeeded.
  static bool ready = false;

  /// Called once in `main`. A failure leaves the app working offline.
  static Future<bool> initialize() async {
    if (!configured) return false;
    try {
      await Supabase.initialize(
        url: url,
        publishableKey: publishableKey,
        // Sign-in uses e-mailed codes, so incoming links (deutschap://…
        // word packs) are never auth callbacks.
        authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
      );
      return ready = true;
    } catch (_) {
      return false;
    }
  }
}

class SupabaseAccountBackend implements AccountBackend {
  SupabaseAccountBackend(this._client);
  final SupabaseClient _client;

  @override
  bool get configured => true;

  static AccountUser? _user(User? u) => u == null ? null : AccountUser(id: u.id, email: u.email);

  @override
  AccountUser? get user => _user(_client.auth.currentUser);

  @override
  Stream<AccountUser?> get userChanges => _client.auth.onAuthStateChange.map((s) => _user(s.session?.user));

  @override
  Future<void> sendCode(String email) => _guard(() => _client.auth.signInWithOtp(email: email, shouldCreateUser: true));

  @override
  Future<void> verifyCode(String email, String code) => _guard(() => _client.auth.verifyOTP(type: OtpType.email, email: email, token: code));

  @override
  Future<void> signOut() => _guard(() => _client.auth.signOut());

  @override
  Future<void> deleteAccount() => _guard(() async {
        await _client.rpc<void>('delete_my_account');
        await _client.auth.signOut();
      });

  @override
  RemoteBackupStore get backups => _SupabaseBackups(_client);

  static Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on AuthException catch (e) {
      throw AccountException(switch (e.code) {
        'otp_expired' => 'Kodun süresi dolmuş ya da kod yanlış. Yeni bir kod iste.',
        'over_email_send_rate_limit' || 'over_request_rate_limit' => 'Çok sık denendi. Birkaç dakika sonra tekrar dene.',
        'email_address_invalid' => 'Bu e-posta adresi geçerli görünmüyor.',
        _ => 'Giriş yapılamadı (${e.message}).',
      });
    } on PostgrestException catch (e) {
      throw AccountException('Sunucu isteği reddetti (${e.message}).');
    } on AccountException {
      rethrow;
    } on RevisionConflict {
      rethrow;
    } catch (e) {
      throw AccountException('Sunucuya ulaşılamadı. İnternet bağlantını kontrol et. ($e)');
    }
  }
}

class _SupabaseBackups implements RemoteBackupStore {
  _SupabaseBackups(this._client);
  final SupabaseClient _client;

  @override
  Future<RemoteBackup?> fetch() => SupabaseAccountBackend._guard(() async {
        final row = await _client.from('backups').select('revision, data, device, updated_at').maybeSingle();
        if (row == null) return null;
        return RemoteBackup(
          revision: (row['revision'] as num).toInt(),
          data: row['data'] as String,
          device: row['device'] as String?,
          updatedAt: DateTime.parse(row['updated_at'] as String).toLocal(),
        );
      });

  @override
  Future<int> push(String data, {required int schema, required String device, required int? expectedRevision}) =>
      SupabaseAccountBackend._guard(() async {
        final rev = await _client.rpc<dynamic>('push_backup', params: {
          'p_data': data,
          'p_schema': schema,
          'p_device': device,
          'p_expected': expectedRevision,
        });
        // The function returns null when the expected revision is stale.
        if (rev == null) throw const RevisionConflict();
        return (rev as num).toInt();
      });
}
