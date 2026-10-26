import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/db/kv_store.dart';
import 'content_bundle.dart';
import 'content_validator.dart';
import 'json_utils.dart';

/// Content files downloaded from an update source, kept in the database and
/// used instead of the bundled files of the same name. Only data travels
/// this way (JSON in the existing schema); nothing is executed.
class ContentOverrides {
  const ContentOverrides({required this.version, required this.files, this.source, this.notesTr});
  final String version;
  final Map<String, String> files;
  final String? source;
  final String? notesTr;

  static const _key = 'content_overrides';

  static Future<ContentOverrides?> load(KvStore kv) async {
    final j = await kv.getJson(_key);
    final files = (j['files'] as Map?)?.cast<String, String>();
    if (files == null || files.isEmpty) return null;
    return ContentOverrides(version: j['version'] as String? ?? '?', files: files, source: j['source'] as String?, notesTr: j['notes_tr'] as String?);
  }

  Future<void> save(KvStore kv) => kv.setJson(_key, {'version': version, 'files': files, 'source': source, 'notes_tr': notesTr});

  static Future<void> clear(KvStore kv) => kv.set(_key, '{}');
}

/// Why an update was not installed.
class ContentUpdateException implements Exception {
  ContentUpdateException(this.messageTr);
  final String messageTr;
  @override
  String toString() => messageTr;
}

/// Downloads a content update described by a manifest:
///
/// ```json
/// {"format": 1, "version": "2026.11.1", "notes_tr": "…",
///  "files": {"stories.json": "https://…/stories.json"}}
/// ```
///
/// Every file must be one of [ContentBundle.files]. The merged content must
/// parse and pass [ContentValidator] before anything is stored, so a broken
/// update can never replace working content.
class ContentUpdater {
  ContentUpdater({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const maxFileBytes = 5 * 1024 * 1024;

  static bool allowedUrl(Uri u) =>
      u.scheme == 'https' || (u.scheme == 'http' && (u.host == 'localhost' || u.host == '127.0.0.1' || u.host.endsWith('.localhost')));

  Future<String> _get(Uri u) async {
    if (!allowedUrl(u)) throw ContentUpdateException('Sadece https adresleri kabul edilir: $u');
    final r = await _client.get(u).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw ContentUpdateException('İndirilemedi (${r.statusCode}): $u');
    if (r.bodyBytes.length > maxFileBytes) throw ContentUpdateException('Dosya çok büyük: $u');
    return utf8.decode(r.bodyBytes);
  }

  /// Fetches and checks an update. Returns the overrides to store; does
  /// not store them.
  Future<ContentOverrides> fetch(String manifestUrl, {required Map<String, String> bundled}) async {
    final base = Uri.tryParse(manifestUrl.trim());
    if (base == null || !base.hasScheme) throw ContentUpdateException('Geçersiz adres.');
    final Map<String, dynamic> manifest;
    try {
      manifest = (jsonDecode(await _get(base)) as Map).cast<String, dynamic>();
    } on FormatException {
      throw ContentUpdateException('Güncelleme bilgisi (manifest) okunamadı.');
    }
    if (manifest['format'] != 1) throw ContentUpdateException('Bu güncelleme biçimi bu uygulama sürümünde desteklenmiyor.');
    final files = (manifest['files'] as Map?)?.cast<String, dynamic>() ?? const {};
    if (files.isEmpty) throw ContentUpdateException('Güncellemede dosya yok.');
    final downloaded = <String, String>{};
    for (final e in files.entries) {
      if (!ContentBundle.files.contains(e.key)) throw ContentUpdateException('Bilinmeyen içerik dosyası: ${e.key}');
      downloaded[e.key] = await _get(base.resolve(e.value as String));
    }
    final merged = {...bundled, ...downloaded};
    final ContentBundle bundle;
    try {
      bundle = ContentBundle.fromSources(merged);
    } on ContentFormatException catch (e) {
      throw ContentUpdateException('Güncellenen içerik okunamadı: ${e.message}');
    }
    final problems = ContentValidator(bundle, merged).validate();
    if (problems.isNotEmpty) {
      throw ContentUpdateException('Güncellenen içerik kontrolden geçemedi (${problems.length} sorun), örneğin: ${problems.first}');
    }
    return ContentOverrides(
      version: manifest['version'] as String? ?? '?',
      files: downloaded,
      source: manifestUrl.trim(),
      notesTr: manifest['notes_tr'] as String?,
    );
  }
}
