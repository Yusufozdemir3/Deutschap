import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/clock.dart';
import '../../../ui/widgets.dart';
import '../data/data_repository.dart';

/// Saving a backup file and restoring from one (or from pasted text when
/// the platform has no file picker).
class BackupCard extends ConsumerWidget {
  const BackupCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Yedek', style: context.text.titleSmall),
      const SizedBox(height: 4),
      Text('Telefon değiştirirken ilerlemen kaybolmasın: yedeği bir dosyaya kaydet, yeni cihazda geri yükle. Dosya sadece senin seçtiğin yere gider.', style: context.text.bodySmall),
      const SizedBox(height: 10),
      FilledButton.tonalIcon(
        onPressed: () => saveBackupFile(context, ref),
        icon: const Icon(Icons.save_alt_rounded),
        label: const Text('Yedek dosyası kaydet'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: () => _pickAndRestore(context, ref),
        icon: const Icon(Icons.settings_backup_restore_rounded),
        label: const Text('Yedekten geri yükle'),
      ),
      TextButton(
        onPressed: () => _pasteAndRestore(context, ref),
        child: const Text('Panodaki yedeği geri yükle'),
      ),
    ]);
  }

  Future<void> _pickAndRestore(BuildContext context, WidgetRef ref) async {
    String text;
    try {
      final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: const ['json']);
      if (files.isEmpty) return;
      text = await files.first.xFile.readAsString();
    } catch (e) {
      if (context.mounted) showToast(context, 'Dosya açılamadı: $e');
      return;
    }
    if (context.mounted) await restoreFromText(context, ref, text);
  }

  Future<void> _pasteAndRestore(BuildContext context, WidgetRef ref) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text ?? '';
    if (!context.mounted) return;
    if (text.trim().isEmpty) {
      showToast(context, 'Pano boş');
      return;
    }
    await restoreFromText(context, ref, text);
  }
}

String backupFileName(DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'deutschap-yedek-${now.year}-${two(now.month)}-${two(now.day)}.json';
}

Future<void> saveBackupFile(BuildContext context, WidgetRef ref) async {
  final json = await ref.read(dataRepositoryProvider).exportJson();
  try {
    final uri = await FilePicker.saveFile(
      fileName: backupFileName(ref.read(clockProvider)()),
      bytes: Uint8List.fromList(utf8.encode(json)),
      mimeType: 'application/json',
      dialogTitle: 'Yedeği kaydet',
    );
    if (!context.mounted) return;
    // Mobile and desktop return null when the dialog is cancelled; the
    // web download always returns null.
    showToast(context, uri == null && !kIsWeb ? 'Kaydedilmedi' : 'Yedek kaydedildi (${(json.length / 1024).toStringAsFixed(1)} KB)');
  } catch (_) {
    // No file system access (e.g. an old browser): fall back to the clipboard.
    await Clipboard.setData(ClipboardData(text: json));
    if (context.mounted) showToast(context, 'Dosya kaydedilemedi; yedek panoya kopyalandı');
  }
}

/// Shows what the backup contains and replaces the learner's data on
/// confirmation. Returns true when data was restored.
Future<bool> restoreFromText(BuildContext context, WidgetRef ref, String text) async {
  final BackupSummary backup;
  try {
    backup = DataRepository.inspect(text);
  } on BackupFormatException catch (e) {
    showToast(context, e.message);
    return false;
  }
  final when = backup.exportedAt;
  final date = when == null ? 'tarihi bilinmiyor' : '${when.day}.${when.month}.${when.year} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
  final ok = await confirm(
    context,
    title: 'Yedek geri yüklensin mi?',
    message: 'Yedek: $date\n${backup.words} kelime · ${backup.lessons} ders · ${backup.episodes} bölüm · ${backup.reviews} tekrar\n\nBu cihazdaki şimdiki verilerin yedektekilerle değiştirilir.',
    confirmLabel: 'Geri yükle',
    destructive: true,
  );
  if (!ok) return false;
  try {
    await ref.read(dataRepositoryProvider).restore(backup);
  } on BackupFormatException catch (e) {
    if (context.mounted) showToast(context, e.message);
    return false;
  }
  ref.bumpData();
  await ref.read(profileProvider.notifier).reload();
  if (context.mounted) showToast(context, 'Yedek geri yüklendi');
  return true;
}
