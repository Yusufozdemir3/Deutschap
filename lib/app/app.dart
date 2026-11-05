import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/account/application/account_providers.dart';
import '../ui/widgets.dart';
import 'providers.dart';
import 'router.dart';
import 'theme/app_theme.dart';

class DeutschapApp extends ConsumerWidget {
  const DeutschapApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boot = ref.watch(bootstrapProvider);
    final light = AppTheme.build(Brightness.light);
    final dark = AppTheme.build(Brightness.dark);

    Widget plain(Widget home) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: light,
          darkTheme: dark,
          home: home,
        );

    if (boot.hasError) {
      return plain(Scaffold(
        body: ErrorState(
          message: 'Deutschap başlatılamadı.',
          details: 'Verilerin cihazında duruyor ve silinmedi. Uygulamayı tekrar başlatmayı dene.\n\n${boot.error}',
          onRetry: () => ref.invalidate(bootstrapProvider),
        ),
      ));
    }
    if (!boot.hasValue) return plain(const SplashScreen());

    final profile = ref.watch(profileProvider);
    if (!profile.hasValue) {
      return plain(profile.hasError
          ? Scaffold(body: ErrorState(message: 'Profil yüklenemedi.', onRetry: () => ref.invalidate(profileProvider)))
          : const SplashScreen());
    }

    return MaterialApp.router(
      title: 'Deutschap',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => _AccountSync(child: child!),
    );
  }
}

/// Syncs the account (if signed in) right after sign-in, at start, when
/// the app comes back and shortly after local changes.
class _AccountSync extends ConsumerStatefulWidget {
  const _AccountSync({required this.child});
  final Widget child;
  @override
  ConsumerState<_AccountSync> createState() => _AccountSyncState();
}

class _AccountSyncState extends ConsumerState<_AccountSync> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(syncControllerProvider.notifier).run(quiet: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Another device may have synced in the meantime.
    if (state == AppLifecycleState.resumed) ref.read(syncControllerProvider.notifier).run(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(dataRevisionProvider, (_, _) => ref.read(syncControllerProvider.notifier).schedule());
    // Right after signing in (e.g. back from Google): first sync.
    ref.listen(accountUserProvider, (prev, next) {
      if (prev?.valueOrNull == null && next.valueOrNull != null) ref.read(syncControllerProvider.notifier).run(quiet: true);
    });
    return widget.child;
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Deutschap', style: context.text.displaySmall!.copyWith(fontFamily: 'Literata')),
              const SizedBox(height: 8),
              Text('Hikâyelerle Almanca', style: context.text.bodyMedium!.copyWith(color: context.palette.inkMuted)),
              const SizedBox(height: 28),
              const SizedBox(width: 120, child: LinearProgressIndicator()),
            ],
          ),
        ),
      );
}
