import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/router.dart';
import 'features/account/data/supabase_backend.dart';
import 'features/notifications/application/notification_service.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  // Accounts are optional; without a configured server this is a no-op.
  await BackendConfig.initialize();
  // A tapped reminder opens its screen; otherwise the platform route.
  final initial = await LocalNotificationService.coldStartRoute() ?? binding.platformDispatcher.defaultRouteName;
  runApp(ProviderScope(
    overrides: [
      if (initial.length > 1 && initial.startsWith('/')) initialLocationProvider.overrideWithValue(initial),
    ],
    child: const DeutschapApp(),
  ));
}
