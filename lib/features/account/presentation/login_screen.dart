import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../application/account_providers.dart';
import 'account_screen.dart';

/// First screen of a build with an account server: the app is used with an
/// account. Once signed in and the first sync has decided which data this
/// device shows, the router moves on by itself.
class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preparing = ref.watch(accountGateProvider) == AccountGate.preparing;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: pagePadding,
          children: [
            PageWidth(
              child: preparing
                  ? Column(
                      children: [
                        const SizedBox(height: 96),
                        const Center(child: CircularProgressIndicator()),
                        const SizedBox(height: 16),
                        Text('Hesabın hazırlanıyor…', style: context.text.titleMedium, textAlign: TextAlign.center),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 48),
                        Text('Deutschap', style: context.text.displaySmall, textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        const SignInPanel(),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
