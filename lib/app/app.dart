import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/account/application/account_providers.dart';
import '../features/notifications/application/notification_providers.dart';
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

    final prefs = profile.requireValue;
    return MaterialApp.router(
      title: 'Deutschap',
      debugShowCheckedModeBanner: false,
      theme: prefs.readableFont ? AppTheme.build(Brightness.light, readableFont: true) : light,
      darkTheme: prefs.readableFont ? AppTheme.build(Brightness.dark, readableFont: true) : dark,
      themeMode: switch (prefs.themeMode) { 'light' => ThemeMode.light, 'dark' => ThemeMode.dark, _ => ThemeMode.system },
      // The learner's text size multiplies the system setting.
      builder: (context, child) {
        child = _BackgroundSync(child: child!);
        if (prefs.textScale == 1.0) return child;
        final mq = MediaQuery.of(context);
        return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(mq.textScaler.scale(1) * prefs.textScale)), child: child);
      },
      routerConfig: ref.watch(routerProvider),
    );
  }
}

/// Background upkeep while the app runs: keeps scheduled reminders in step
/// with data and preferences, and syncs the account (if signed in) at start,
/// when the app comes back and shortly after local changes.
class _BackgroundSync extends ConsumerStatefulWidget {
  const _BackgroundSync({required this.child});
  final Widget child;
  @override
  ConsumerState<_BackgroundSync> createState() => _BackgroundSyncState();
}

class _BackgroundSyncState extends ConsumerState<_BackgroundSync> with WidgetsBindingObserver {
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
    if (state != AppLifecycleState.resumed) return;
    // The day may have changed, and another device may have synced.
    ref.invalidate(notificationFactsProvider);
    ref.read(syncControllerProvider.notifier).run(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notificationSyncProvider);
    ref.listen(dataRevisionProvider, (_, _) => ref.read(syncControllerProvider.notifier).schedule());
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
              Text('Deutschap', style: context.text.displaySmall!.copyWith(fontFamily: context.serif)),
              const SizedBox(height: 8),
              Text('Hikâyelerle Almanca', style: context.text.bodyMedium!.copyWith(color: context.palette.inkMuted)),
              const SizedBox(height: 28),
              const SizedBox(width: 120, child: LinearProgressIndicator()),
            ],
          ),
        ),
      );
}
