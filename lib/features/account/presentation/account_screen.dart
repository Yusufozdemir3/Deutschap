import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../application/account_providers.dart';
import '../application/sync_engine.dart';
import '../domain/account_backend.dart';

/// Account: sign in with Google, keep a copy of all learner data
/// on the server and move it between devices.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(accountBackendProvider);
    final user = ref.watch(accountUserProvider).valueOrNull ?? backend.user;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Hesap ve eşitleme')),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: !backend.configured
                ? const _NotConfigured()
                : user == null
                ? const SignInPanel()
                : _SignedIn(user: user),
          ),
        ],
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 8),
      AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hesap bu sürümde kapalı', style: context.text.titleMedium),
            const SizedBox(height: 8),
            Text('Bu sürümde hesap sunucusu yok; uygulama yalnızca bu cihazda çalışır ve verilerin burada kalır.', style: context.text.bodyMedium),
          ],
        ),
      ),
    ],
  );
}

const _privacy =
    'Uygulamayı kullanmak için Google ile giriş yapman gerekir. Bütün öğrenme verilerin (kelimeler, notlar, ilerleme, ayarlar) şifreli bağlantıyla sunucuda saklanır ve sadece sen erişebilirsin. Reklam ya da analitik için kullanılmaz. Hesabını sildiğinde sunucudaki kopya da hemen silinir.';

class SignInPanel extends ConsumerStatefulWidget {
  const SignInPanel({super.key});
  @override
  ConsumerState<SignInPanel> createState() => _SignInState();
}

class _SignInState extends ConsumerState<SignInPanel> with WidgetsBindingObserver {
  bool _busy = false;
  bool _waitingForReturn = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// On phones Google opens in the browser. Back in the app without a
  /// session means the learner cancelled (or the callback never came).
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_waitingForReturn) return;
    Future<void>.delayed(const Duration(seconds: 4), () {
      if (!mounted || !_waitingForReturn) return;
      final signedIn = (ref.read(accountUserProvider).valueOrNull ?? ref.read(accountBackendProvider).user) != null;
      if (signedIn) return;
      setState(() {
        _waitingForReturn = false;
        _busy = false;
        _error = 'Giriş tamamlanmadı. İstersen tekrar dene.';
      });
    });
  }

  Future<void> _google() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountBackendProvider).signInWithGoogle();
      _waitingForReturn = !kIsWeb;
      if (kIsWeb && mounted) setState(() => _busy = false);
    } on AccountException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final expired = ref.watch(syncControllerProvider.select((s) => s.sessionExpired));
    // A failed return from Google is delivered as a stream error.
    final streamError = ref.watch(accountUserProvider).error;
    final error = _error ?? (streamError is AccountException ? streamError.message : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        if (expired)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AppCard(
              child: Row(children: [
                Icon(Icons.info_outline_rounded, color: context.palette.danger),
                const SizedBox(width: 10),
                Expanded(child: Text('Oturumun sona erdi. Eşitlemeye devam etmek için tekrar giriş yap. Verilerin bu cihazda duruyor.', style: context.text.bodyMedium)),
              ]),
            ),
          ),
        Text('Verilerin her cihazda', style: context.text.headlineSmall),
        const SizedBox(height: 6),
        Text('Google hesabınla giriş yap. Aynı hesapla başka bir cihazda giriş yaptığında kelimelerin ve ilerlemen oraya da gelir.', style: context.text.bodyMedium),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _busy ? null : _google, icon: const Icon(Icons.account_circle_outlined), label: Text(_busy ? 'Google açılıyor…' : 'Google ile giriş yap')),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error, style: context.text.bodySmall!.copyWith(color: context.palette.danger)),
          ),
        const SizedBox(height: 16),
        Text(_privacy, style: context.text.bodySmall),
      ],
    );
  }
}

class _SignedIn extends ConsumerWidget {
  const _SignedIn({required this.user});
  final AccountUser user;

  static String _when(DateTime t) => '${t.day}.${t.month}.${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncControllerProvider);
    final sync = ref.read(syncControllerProvider.notifier);
    final p = context.palette;
    final both = s.last?.bothChanged ?? false;
    final status = switch (s.last?.outcome) {
      _ when s.busy => 'Eşitleniyor…',
      SyncOutcome.pushed when both => 'İki tarafta da değişiklik vardı; bu cihazdakiler daha yeniydi ve hesabına yüklendi.',
      SyncOutcome.pulled when both => 'İki tarafta da değişiklik vardı; hesabındakiler daha yeniydi ve bu cihaza alındı.',
      SyncOutcome.pushed => 'Bu cihazdaki veriler hesabına yüklendi.',
      SyncOutcome.pulled => 'Hesabındaki veriler bu cihaza alındı.',
      SyncOutcome.upToDate => 'Her şey güncel.',
      null => s.meta == null ? 'Henüz eşitlenmedi.' : 'Son eşitleme: ${_when(s.meta!.syncedAt)}',
    };

    Future<void> run() async {
      final r = await sync.run();
      if (!context.mounted) return;
      final err = ref.read(syncControllerProvider).error;
      if (err != null) showToast(context, err);
      if (r?.outcome == SyncOutcome.pulled) showToast(context, 'Hesabındaki veriler alındı');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.cloud_done_outlined, color: p.success),
                  const SizedBox(width: 10),
                  Expanded(child: Text(user.email ?? 'Giriş yapıldı', style: context.text.titleMedium)),
                ],
              ),
              const SizedBox(height: 10),
              Text(status, style: context.text.bodyMedium),
              if (s.error != null) Text('Son eşitleme denemesi başarısız: ${s.error}', style: context.text.bodySmall!.copyWith(color: p.danger)),
              if (s.meta != null && s.last != null) Text('Son eşitleme: ${_when(s.meta!.syncedAt)}', style: context.text.bodySmall),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(onPressed: s.busy ? null : run, icon: const Icon(Icons.sync_rounded), label: const Text('Şimdi eşitle')),
              const SizedBox(height: 6),
              Text(
                'Uygulamayı açtığında ve bir değişiklikten kısa süre sonra kendiliğinden eşitlenir. İki cihazda da değişiklik yapıldıysa en son yapılan kalır.',
                style: context.text.bodySmall,
              ),
            ],
          ),
        ),
        const SectionTitle('Hesap'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: s.busy
                    ? null
                    : () async {
                        if (!await confirm(context, title: 'Çıkış yapılsın mı?', message: 'Çıkınca uygulamayı kullanmak için tekrar giriş yapman gerekir. Verilerin hesabında durur.', confirmLabel: 'Çıkış yap')) return;
                        await sync.signOut();
                      },
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Çıkış yap'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(foregroundColor: p.danger),
                onPressed: s.busy ? null : () => _delete(context, ref),
                icon: const Icon(Icons.person_remove_outlined),
                label: const Text('Hesabı ve sunucudaki verileri sil'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(_privacy, style: context.text.bodySmall),
      ],
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Hesap silinsin mi?',
      message: 'Hesabın ve sunucudaki bütün verilerin kalıcı olarak silinir. Bu cihazdaki veriler de silinir.',
      confirmLabel: 'Hesabı sil',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(syncControllerProvider.notifier).deleteAccount();
      if (context.mounted) showToast(context, 'Hesabın silindi');
    } on AccountException catch (e) {
      if (context.mounted) showToast(context, e.message);
    }
  }
}
