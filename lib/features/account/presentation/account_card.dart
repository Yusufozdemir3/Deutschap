import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../application/account_providers.dart';

/// Entry to the account screen at the top of the settings. Hidden when the
/// build has no account server.
class AccountCard extends ConsumerWidget {
  const AccountCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backend = ref.watch(accountBackendProvider);
    if (!backend.configured) return const SizedBox.shrink();
    final user = ref.watch(accountUserProvider).valueOrNull ?? backend.user;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppCard(
        onTap: () => context.push('/account'),
        child: Row(children: [
          Icon(user == null ? Icons.cloud_off_outlined : Icons.cloud_done_outlined),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(user == null ? 'Hesap' : (user.email ?? 'Hesap')),
              Text(user == null ? 'Google ile giriş yap, verilerini cihazlar arasında eşitle' : 'Eşitleme açık', style: context.text.bodySmall),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded),
        ]),
      ),
    );
  }
}
