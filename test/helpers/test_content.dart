import 'dart:io';

import 'package:deutschap/content/content_bundle.dart';

Map<String, String> loadContentSources() => {
      for (final f in ContentBundle.files) f: File('assets/content/$f').readAsStringSync(),
    };

ContentBundle? _cached;

/// The real shipped content, parsed once per test isolate.
ContentBundle loadTestContent() => _cached ??= ContentBundle.fromSources(loadContentSources());
