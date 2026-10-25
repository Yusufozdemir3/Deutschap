import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../application/vocab_providers.dart';
import '../data/vocab_repository.dart';
import '../domain/vocab_entry.dart';
import '../domain/vocab_status.dart';
import 'word_sheet.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _update(VocabQuery Function(VocabQuery q) f) => ref.read(vocabQueryProvider.notifier).update(f);

  @override
  Widget build(BuildContext context) {
    final q = ref.watch(vocabQueryProvider);
    final list = ref.watch(vocabListProvider);
    final total = ref.watch(vocabCountProvider).valueOrNull ?? 0;
    final due = ref.watch(dueCountProvider).valueOrNull ?? 0;
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kelimelerim'),
        actions: [
          IconButton(tooltip: 'Sözlük', icon: const Icon(Icons.menu_book_outlined), onPressed: () => context.push('/dictionary')),
          IconButton(tooltip: 'Koleksiyonlar', icon: const Icon(Icons.collections_bookmark_outlined), onPressed: () => context.push('/collections')),
          IconButton(tooltip: 'Kelime ekle', icon: const Icon(Icons.add_rounded), onPressed: () => showManualAddDialog(context, ref)),
        ],
      ),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              AppCard(
                color: due > 0 ? p.accentSoft : null,
                borderColor: due > 0 ? p.accent : null,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(due > 0 ? '$due tekrar seni bekliyor' : (total == 0 ? 'Kelime defterin boş' : 'Şu an tekrar zamanı gelen kelime yok'), style: context.text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    due > 0
                        ? 'Tam unutmadan önce hatırlamak en verimli tekrardır. İstediğin kadar yap, istediğin an bırak.'
                        : (total == 0 ? 'Hikâyelerde, derslerde ve okumalarda bir kelimeye dokun, "Kaydet"e bas. Burada cümlesiyle birlikte toplanır.' : 'Bir sonraki tekrar zamanı gelince burada görünür. Yeni kelimeler keşfetmeye ne dersin?'),
                    style: context.text.bodySmall,
                  ),
                  if (due > 0) ...[
                    const SizedBox(height: 12),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.icon(onPressed: () => context.push('/review?n=10'), icon: const Icon(Icons.play_arrow_rounded), label: Text('Kısa tekrar (${due < 10 ? due : 10})')),
                      if (due > 10) OutlinedButton(onPressed: () => context.push('/review?n=30'), child: const Text('Uzun oturum (30)')),
                    ]),
                  ],
                ]),
              ),
              const SizedBox(height: 10),
              AppCard(
                onTap: () => context.push('/drill'),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(14)),
                    child: Icon(Icons.fitness_center_rounded, color: p.accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Kelime antrenmanı', style: context.text.titleSmall),
                      Text('Eşleştir, dinle, yaz, artikel ve çoğul çalış. Kaydettiklerinle ya da konuya göre.', style: context.text.bodySmall),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: p.inkMuted),
                ]),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Almanca ya da Türkçe ara',
                  suffixIcon: q.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Temizle',
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _search.clear();
                            _update((q) => VocabQuery(status: q.status, kind: q.kind, sort: q.sort, limit: q.limit));
                          },
                        ),
                ),
                onChanged: (v) => _update((q) => VocabQuery(text: v, status: q.status, kind: q.kind, sort: q.sort, limit: q.limit)),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final k in const [(null, 'Hepsi'), ('noun', 'İsimler'), ('verb', 'Fiiller'), ('expression', 'İfadeler')])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(k.$2),
                        selected: q.kind == k.$1,
                        onSelected: (_) => _update((q) => VocabQuery(text: q.text, status: q.status, kind: k.$1, sort: q.sort, limit: q.limit)),
                      ),
                    ),
                  const SizedBox(width: 8),
                  PopupMenuButton<VocabStatus?>(
                    tooltip: 'Duruma göre filtrele',
                    onSelected: (s) => _update((q) => VocabQuery(text: q.text, status: s, kind: q.kind, sort: q.sort, limit: q.limit)),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: null, child: Text('Tüm durumlar')),
                      for (final s in VocabStatus.values) PopupMenuItem(value: s, child: Text(s.labelTr)),
                    ],
                    child: Chip(avatar: const Icon(Icons.filter_list_rounded, size: 18), label: Text(q.status?.labelTr ?? 'Durum')),
                  ),
                  const SizedBox(width: 6),
                  PopupMenuButton<VocabSort>(
                    tooltip: 'Sırala',
                    onSelected: (s) => _update((q) => VocabQuery(text: q.text, status: q.status, kind: q.kind, sort: s, limit: q.limit)),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: VocabSort.recent, child: Text('En yeni')),
                      PopupMenuItem(value: VocabSort.alphabetical, child: Text('Alfabetik')),
                      PopupMenuItem(value: VocabSort.status, child: Text('Duruma göre')),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.sort_rounded, size: 18),
                      label: Text(switch (q.sort) { VocabSort.recent => 'En yeni', VocabSort.alphabetical => 'A–Z', VocabSort.status => 'Durum' }),
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              AsyncView<List<VocabEntry>>(
                value: list,
                onRetry: () => ref.invalidate(vocabListProvider),
                builder: (entries) {
                  if (entries.isEmpty) {
                    return total == 0
                        ? EmptyState(
                            icon: Icons.bookmarks_outlined,
                            title: 'Henüz kaydedilmiş kelime yok',
                            message: 'Bir kelimeye dokunduğunda açılan panelde "Kaydet"e bas. Kelime, karşılaştığın cümleyle birlikte burada saklanır.',
                            action: FilledButton(onPressed: () => context.go('/lernen?tab=stories'), child: const Text('Bir hikâyeyle başla')),
                          )
                        : const EmptyState(icon: Icons.search_off_rounded, title: 'Sonuç yok', message: 'Aramanı ya da filtreleri değiştirmeyi dene.');
                  }
                  return Column(children: [
                    Align(alignment: Alignment.centerLeft, child: Text('${entries.length}${entries.length >= q.limit ? '+' : ''} kelime', style: context.text.labelSmall)),
                    const SizedBox(height: 6),
                    for (final e in entries) _EntryTile(entry: e),
                  ]);
                },
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry});
  final VocabEntry entry;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final lemma = entry.article != null && entry.headword.startsWith('${entry.article} ') ? entry.headword.substring(entry.article!.length + 1) : entry.headword;
    final statusColor = switch (entry.status) {
      VocabStatus.needsReinforcement => p.dangerSoft,
      VocabStatus.familiar || VocabStatus.temporarilyMastered || VocabStatus.longTermRetained => p.successSoft,
      _ => p.surfaceAlt,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AppCard(
        onTap: () => context.push('/word/${entry.id}'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Headword(lemma: lemma, article: entry.article),
              Text(entry.meaningTr, style: context.text.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          Pill(entry.status.labelTr, color: statusColor),
        ]),
      ),
    );
  }
}
