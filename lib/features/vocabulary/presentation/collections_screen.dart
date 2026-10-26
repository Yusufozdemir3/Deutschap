import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../../sharing/application/pack_service.dart';
import '../../sharing/domain/word_pack.dart';
import '../application/vocab_providers.dart';
import '../data/vocab_repository.dart';
import '../domain/vocab_entry.dart';

class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  static const _suggestions = ['İş Almancası', 'Sürekli unuttuklarım', 'Kullanışlı ifadeler', 'Seyahat', 'Sınav hazırlığı'];

  Future<void> _create(BuildContext context, WidgetRef ref, [String initial = '']) async {
    final c = TextEditingController(text: initial);
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Yeni koleksiyon'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Ör. Kafe kelimeleri')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Oluştur')),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      await ref.read(vocabRepositoryProvider).createCollection(c.text);
      ref.bumpData();
    }
    c.dispose();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cols = ref.watch(collectionsProvider);
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Koleksiyonlar'), actions: [
        IconButton(tooltip: 'İçe aktar', onPressed: () => context.push('/import'), icon: const Icon(Icons.download_rounded)),
        IconButton(tooltip: 'Yeni', onPressed: () => _create(context, ref), icon: const Icon(Icons.add_rounded)),
      ]),
      body: AsyncView<List<CollectionInfo>>(
        value: cols,
        onRetry: () => ref.invalidate(collectionsProvider),
        builder: (list) => ListView(
          padding: pagePadding,
          children: [
            PageWidth(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (list.isEmpty) ...[
                  const EmptyState(icon: Icons.collections_bookmark_outlined, title: 'Henüz koleksiyon yok', message: 'Kelimelerini kendi kategorilerinde topla. Bir kelimenin sayfasından da ekleyebilirsin.'),
                  Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                    for (final s in _suggestions) Tag(s, onTap: () => _create(context, ref, s)),
                  ]),
                ],
                for (final c in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _CollectionView(info: c))),
                      child: Row(children: [
                        const Icon(Icons.folder_outlined),
                        const SizedBox(width: 12),
                        Expanded(child: Text(c.name, style: context.text.titleSmall)),
                        Text('${c.count}', style: context.text.labelSmall),
                      ]),
                    ),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

final _collectionEntriesProvider = FutureProvider.family<List<VocabEntry>, String>((ref, id) {
  ref.watch(dataRevisionProvider);
  return ref.watch(vocabRepositoryProvider).list(VocabQuery(collectionId: id, limit: 500));
});

class _CollectionView extends ConsumerWidget {
  const _CollectionView({required this.info});
  final CollectionInfo info;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(_collectionEntriesProvider(info.id));
    return Scaffold(
      appBar: AppBar(
        title: Text(info.name),
        actions: [
          IconButton(
            tooltip: 'Paylaş',
            icon: const Icon(Icons.qr_code_2_rounded),
            onPressed: () async {
              final entries = await ref.read(vocabRepositoryProvider).list(VocabQuery(collectionId: info.id, limit: WordPack.maxWords));
              final pack = packFromEntries(info.name, entries);
              if (!context.mounted) return;
              if (pack.size == 0) {
                showToast(context, 'Paylaşılacak kelime yok');
                return;
              }
              await context.push('/share', extra: pack);
            },
          ),
          IconButton(
            tooltip: 'Koleksiyonu sil',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: () async {
              final ok = await confirm(context, title: 'Koleksiyonu sil?', message: 'Sadece koleksiyon silinir; içindeki kelimeler defterinde kalır.', confirmLabel: 'Sil', destructive: true);
              if (!ok) return;
              await ref.read(vocabRepositoryProvider).deleteCollection(info.id);
              ref.bumpData();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: AsyncView<List<VocabEntry>>(
        value: entries,
        builder: (list) => list.isEmpty
            ? const EmptyState(icon: Icons.folder_open_outlined, title: 'Koleksiyon boş', message: 'Bir kelimenin sayfasında bu koleksiyonu seçerek ekleyebilirsin.')
            : ListView(
                padding: pagePadding,
                children: [
                  for (final e in list)
                    ListTile(
                      title: Text(e.headword, style: TextStyle(fontFamily: context.serif)),
                      subtitle: Text(e.meaningTr),
                      onTap: () => context.push('/word/${e.id}'),
                    ),
                ],
              ),
      ),
    );
  }
}
