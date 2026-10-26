import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../application/account_providers.dart';
import '../application/sync_engine.dart';
import '../domain/account_backend.dart';

/// Optional account: sign in with an e-mailed code, keep a copy of all
/// learner data on the server and move it between devices.
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
                    ? const _SignIn()
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
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 8),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Hesaplar bu sürümde kapalı', style: context.text.titleMedium),
            const SizedBox(height: 8),
            Text('Uygulama hesapsız tam olarak çalışır. Verilerini bir cihazdan diğerine taşımak için Ayarlar → Verilerin → "Yedek dosyası kaydet" seçeneğini kullanabilirsin.', style: context.text.bodyMedium),
          ]),
        ),
      ]);
}

const _privacy = 'Hesap isteğe bağlıdır. Giriş yaparsan bütün öğrenme verilerin (kelimeler, notlar, ilerleme, ayarlar) şifreli bağlantıyla sunucuya kopyalanır ve sadece sen erişebilirsin. Reklam ya da analitik için kullanılmaz. Hesabını sildiğinde sunucudaki kopya da hemen silinir.';

class _SignIn extends ConsumerStatefulWidget {
  const _SignIn();
  @override
  ConsumerState<_SignIn> createState() => _SignInState();
}

class _SignInState extends ConsumerState<_SignIn> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _emailOk => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim());

  Future<void> _do(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on AccountException catch (e) {
      _error = e.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() => _do(() async {
        await ref.read(accountBackendProvider).sendCode(_email.text.trim());
        _codeSent = true;
      });

  Future<void> _verify() => _do(() async {
        await ref.read(accountBackendProvider).verifyCode(_email.text.trim(), _code.text.trim());
        // First sync right away; a conflict is shown on the next screen.
        await ref.read(syncControllerProvider.notifier).run();
      });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      Text('Verilerin her cihazda', style: context.text.headlineSmall),
      const SizedBox(height: 6),
      Text('Şifre yok: E-posta adresine altı haneli bir kod gönderiyoruz. Aynı adresle başka bir cihazda giriş yaptığında kelimelerin ve ilerlemen oraya da gelir.', style: context.text.bodyMedium),
      const SizedBox(height: 16),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(
            controller: _email,
            enabled: !_codeSent && !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'E-posta'),
            onChanged: (_) => setState(() {}),
          ),
          if (_codeSent) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _code,
              enabled: !_busy,
              autofocus: true,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              maxLength: 8,
              decoration: const InputDecoration(labelText: 'E-postadaki kod'),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _verify(),
            ),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: context.text.bodySmall!.copyWith(color: context.palette.danger))),
          const SizedBox(height: 12),
          if (!_codeSent)
            FilledButton(onPressed: _busy || !_emailOk ? null : _send, child: Text(_busy ? 'Gönderiliyor…' : 'Kod gönder'))
          else ...[
            FilledButton(onPressed: _busy || _code.text.trim().length < 6 ? null : _verify, child: Text(_busy ? 'Kontrol ediliyor…' : 'Giriş yap')),
            TextButton(
              onPressed: _busy ? null : () => setState(() => _codeSent = false),
              child: const Text('Başka bir e-posta kullan'),
            ),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      Text(_privacy, style: context.text.bodySmall),
    ]);
  }
}

class _SignedIn extends ConsumerWidget {
  const _SignedIn({required this.user});
  final AccountUser user;

  static String _when(DateTime t) =>
      '${t.day}.${t.month}.${t.year} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(syncControllerProvider);
    final sync = ref.read(syncControllerProvider.notifier);
    final p = context.palette;
    final status = switch (s.last) {
      _ when s.busy => 'Eşitleniyor…',
      SyncOutcome.pushed => 'Bu cihazdaki veriler hesabına yüklendi.',
      SyncOutcome.pulled => 'Hesabındaki veriler bu cihaza alındı.',
      SyncOutcome.upToDate => 'Her şey güncel.',
      SyncOutcome.conflict => 'İki tarafta da değişiklik var.',
      null => s.meta == null ? 'Henüz eşitlenmedi.' : 'Son eşitleme: ${_when(s.meta!.syncedAt)}',
    };

    Future<void> run([SyncChoice? choice]) async {
      final r = await sync.run(choice: choice);
      if (!context.mounted) return;
      final err = ref.read(syncControllerProvider).error;
      if (err != null) showToast(context, err);
      if (r == SyncOutcome.pulled) showToast(context, 'Hesabındaki veriler alındı');
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 8),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.cloud_done_outlined, color: p.success),
            const SizedBox(width: 10),
            Expanded(child: Text(user.email ?? 'Giriş yapıldı', style: context.text.titleMedium)),
          ]),
          const SizedBox(height: 10),
          Text(status, style: context.text.bodyMedium),
          if (s.meta != null && s.last != null) Text('Son eşitleme: ${_when(s.meta!.syncedAt)}', style: context.text.bodySmall),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: s.busy || s.conflict != null ? null : () => run(),
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Şimdi eşitle'),
          ),
          const SizedBox(height: 6),
          Text('Uygulamayı açtığında ve bir değişiklikten kısa süre sonra kendiliğinden eşitlenir.', style: context.text.bodySmall),
        ]),
      ),
      if (s.conflict != null) ...[
        const SizedBox(height: 12),
        AppCard(
          color: p.accentSoft,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Hangisi kalsın?', style: context.text.titleMedium),
            const SizedBox(height: 6),
            Text('Hem bu cihazda hem de hesabında (${s.conflict!.device ?? 'başka cihaz'}, ${_when(s.conflict!.updatedAt)}) son eşitlemeden sonra değişiklik yapılmış. Biri diğerinin yerine geçecek. Emin değilsen önce Ayarlar\'dan bu cihazın yedeğini kaydet.', style: context.text.bodyMedium),
            const SizedBox(height: 12),
            FilledButton(onPressed: s.busy ? null : () => run(SyncChoice.keepDevice), child: const Text('Bu cihazdakini kullan')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: s.busy ? null : () => run(SyncChoice.takeAccount), child: const Text('Hesaptakini bu cihaza al')),
          ]),
        ),
      ],
      const SectionTitle('Hesap'),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          OutlinedButton.icon(
            onPressed: s.busy
                ? null
                : () async {
                    if (!await confirm(context, title: 'Çıkış yapılsın mı?', message: 'Bu cihazdaki verilerin kalır; sadece eşitleme durur.', confirmLabel: 'Çıkış yap')) return;
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
        ]),
      ),
      const SizedBox(height: 16),
      Text(_privacy, style: context.text.bodySmall),
    ]);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Hesap silinsin mi?',
      message: 'Hesabın ve sunucudaki bütün verilerin kalıcı olarak silinir. Bu cihazdaki veriler kalır.',
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
