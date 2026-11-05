import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/account_backend.dart';

/// Build-time configuration, e.g.
/// `flutter run --dart-define-from-file=supabase.local.json` (see docs/ACCOUNTS.md).
/// The publishable key is meant to ship in clients; row-level security on
/// the server (supabase/migrations) decides what it may read and write.
class BackendConfig {
  static const url = String.fromEnvironment('SUPABASE_URL');
  static const publishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static bool get configured => url.isNotEmpty && publishableKey.isNotEmpty;

  /// True once [initialize] succeeded.
  static bool ready = false;

  /// Where Google sends the learner back after signing in. Both must be
  /// listed under Authentication → URL Configuration in Supabase.
  static String get redirectUrl => kIsWeb ? '${Uri.base.origin}/' : 'deutschap://login-callback';

  static bool isAuthCallback(Uri uri) {
    if (!kIsWeb && uri.host != 'login-callback') return false;
    final fragment = Uri.splitQueryString(uri.fragment.contains('=') ? uri.fragment : '');
    bool has(String k) => uri.queryParameters.containsKey(k) || fragment.containsKey(k);
    return has('code') || has('access_token') || has('error_description');
  }

  /// Called once in `main`. A failure leaves the app working offline.
  static Future<bool> initialize() async {
    if (!configured) return false;
    try {
      await Supabase.initialize(
        url: url,
        publishableKey: publishableKey,
        // Google sign-in returns to the page itself (web) or to
        // deutschap://login-callback (apps).
        authOptions: const FlutterAuthClientOptions(detectSessionInUriPredicate: isAuthCallback),
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
  Stream<AccountUser?> get userChanges => _client.auth.onAuthStateChange
      .map((s) => _user(s.session?.user))
      // A failed return from Google (cancelled, denied) arrives as a stream error.
      .transform(StreamTransformer<AccountUser?, AccountUser?>.fromHandlers(
        handleError: (e, st, sink) => sink.addError(e is AuthException ? AccountException(_signInMessage(e)) : e, st),
      ));

  @override
  Future<void> signInWithGoogle() => _guard(() async {
        // Web leaves the page and comes back signed in; apps open the
        // browser and return through the deutschap://login-callback link.
        await _client.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: BackendConfig.redirectUrl,
          authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
        );
      });

  @override
  Future<void> signOut() async {
    // Local scope: ending the session on this device must work offline.
    try {
      await _client.auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Nothing to tell the learner; the session is dropped locally below.
    }
  }

  @override
  Future<void> deleteAccount() => _guard(() async {
        await _client.rpc<void>('delete_my_account');
        try {
          await _client.auth.signOut(scope: SignOutScope.local);
        } catch (_) {
          // The user no longer exists on the server; the local session is moot.
        }
      });

  @override
  RemoteBackupStore get backups => _SupabaseBackups(_client);

  static String _signInMessage(AuthException e) {
    final text = '${e.code ?? ''} ${e.message}'.toLowerCase();
    if (e.code == 'over_request_rate_limit') return 'Çok sık denendi. Birkaç dakika sonra tekrar dene.';
    if (text.contains('access_denied') || text.contains('cancel') || text.contains('denied')) return 'Giriş iptal edildi. İstersen tekrar dene.';
    return 'Giriş yapılamadı (${e.message}).';
  }

  static Future<T> _guard<T>(Future<T> Function() f) async {
    try {
      return await f();
    } on AuthException catch (e) {
      throw AccountException(_signInMessage(e));
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
