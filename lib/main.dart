import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/router.dart';

void main() {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final initial = binding.platformDispatcher.defaultRouteName;
  runApp(ProviderScope(
    overrides: [
      if (initial.length > 1 && initial.startsWith('/')) initialLocationProvider.overrideWithValue(initial),
    ],
    child: const DeutschapApp(),
  ));
}
