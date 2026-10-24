import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    );
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
