import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../data/reading_repository.dart';

/// Import of the learner's own German text via paste. The text is stored
/// only on this device and never uploaded.
class PasteTextScreen extends ConsumerStatefulWidget {
  const PasteTextScreen({super.key});
  @override
  ConsumerState<PasteTextScreen> createState() => _PasteTextScreenState();
}

class _PasteTextScreenState extends ConsumerState<PasteTextScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      showToast(context, 'Panoda metin yok.');
      return;
    }
    setState(() => _body.text = text);
  }

  Future<void> _save() async {
    final text = _body.text.trim();
    if (text.isEmpty || _saving) return;
    if (text.length > ReadingRepository.maxPastedChars) {
      showToast(context, 'Metin çok uzun (en fazla ${ReadingRepository.maxPastedChars} karakter). Bir bölümünü ekle.');
      return;
    }
    setState(() => _saving = true);
    try {
      final id = await ref.read(readingRepositoryProvider).addPasted(_title.text, text);
      ref.bumpData();
      if (mounted) context.pushReplacement('/reader/$id');
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        showToast(context, 'Metin kaydedilemedi. Tekrar dene.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final len = _body.text.length;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Kendi metnini ekle')),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Almanca bir metin yapıştır: bir e-posta, haber, şarkı sözü ya da ders notu. Her kelimeye dokunup anlamını görebilirsin.', style: context.text.bodyMedium),
              const SizedBox(height: 6),
              Text('Metin sadece bu cihazda saklanır, hiçbir yere gönderilmez. Telif hakkıyla korunan içerikleri yalnızca kişisel kullanım için ekle.', style: context.text.bodySmall),
              const SizedBox(height: 16),
              TextField(controller: _title, decoration: const InputDecoration(labelText: 'Başlık (isteğe bağlı)')),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                minLines: 8,
                maxLines: 16,
                style: context.reading.copyWith(fontSize: 17),
                decoration: const InputDecoration(hintText: 'Metni buraya yapıştır…', alignLabelWithHint: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 6),
              Text('$len / ${ReadingRepository.maxPastedChars}', style: context.text.labelSmall, textAlign: TextAlign.end),
              const SizedBox(height: 12),
              OutlinedButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste_rounded), label: const Text('Panodan yapıştır')),
              const SizedBox(height: 8),
              FilledButton(onPressed: _body.text.trim().isEmpty || _saving ? null : _save, child: const Text('Okumaya başla')),
              const SizedBox(height: 16),
              Text('PDF/EPUB içe aktarma bu sürümde yok. Taranmış belgeler için metin tanıma (OCR) ileride, açık izninle eklenecek.', style: context.text.bodySmall),
            ]),
          ),
        ],
      ),
    );
  }
}
