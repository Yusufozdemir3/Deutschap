import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/content_updates.dart';
import '../../../ui/widgets.dart';

/// Install new stories, texts and lessons from an update source without a
/// store update. The source is a manifest URL (see docs/CONTENT_UPDATES.md).
class ContentUpdateCard extends ConsumerStatefulWidget {
  const ContentUpdateCard({super.key});
  @override
  ConsumerState<ContentUpdateCard> createState() => _ContentUpdateCardState();
}

class _ContentUpdateCardState extends ConsumerState<ContentUpdateCard> {
  final _url = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url.text = ref.read(bootstrapProvider).valueOrNull?.overrides?.source ?? '';
  }

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    final services = ref.read(bootstrapProvider).requireValue;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final update = await ContentUpdater().fetch(_url.text, bundled: services.bundledSources);
      await update.save(ref.read(kvStoreProvider));
      if (!mounted) return;
      showToast(context, 'İçerik güncellendi (${update.version}). Uygulama yeniden yükleniyor…');
      ref.invalidate(bootstrapProvider);
    } on ContentUpdateException catch (e) {
      if (mounted) setState(() => _error = e.messageTr);
    } catch (e) {
      if (mounted) setState(() => _error = 'Bağlantı kurulamadı. İnternet bağlantını ve adresi kontrol et.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revert() async {
    await ContentOverrides.clear(ref.read(kvStoreProvider));
    ref.invalidate(bootstrapProvider);
  }

  @override
  Widget build(BuildContext context) {
    final services = ref.watch(bootstrapProvider).valueOrNull;
    final overrides = services?.overrides;
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('İçerik güncellemeleri', style: context.text.titleSmall),
      const SizedBox(height: 4),
      Text(
        overrides == null
            ? 'Uygulamayla gelen içerik kullanılıyor (sözlük sürümü ${services?.content.version ?? '?'}).'
            : 'Güncellenmiş içerik kullanılıyor: ${overrides.version} · ${overrides.files.length} dosya${overrides.notesTr == null ? '' : '\n${overrides.notesTr}'}',
        style: context.text.bodySmall,
      ),
      const SizedBox(height: 8),
      Text('Yeni hikâye, metin ve dersleri mağaza güncellemesi beklemeden yükleyebilirsin. İçerik indirilir, uygulamanın kontrollerinden '
          'geçerse kullanılır; geçmezse hiçbir şey değişmez. Sadece metin içerik iner, kod çalıştırılmaz.', style: context.text.bodySmall!.copyWith(color: p.inkMuted)),
      const SizedBox(height: 8),
      TextField(
        controller: _url,
        keyboardType: TextInputType.url,
        decoration: const InputDecoration(labelText: 'Güncelleme adresi (manifest)', hintText: 'https://…/deutschap/manifest.json'),
        onChanged: (_) => setState(() {}),
      ),
      if (_error != null) ...[
        const SizedBox(height: 8),
        FeedbackPanel(positive: false, title: 'Güncelleme yüklenmedi', body: _error),
      ],
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: _busy || _url.text.trim().isEmpty ? null : _check,
          icon: _busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.system_update_alt_rounded),
          label: const Text('Denetle ve yükle'),
        ),
        if (overrides != null) OutlinedButton(onPressed: _revert, child: const Text('Uygulamayla gelen içeriğe dön')),
      ]),
    ]);
  }
}
