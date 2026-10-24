import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/clock.dart';
import '../../../ui/widgets.dart';
import '../../review/domain/scheduler.dart';
import '../application/vocab_providers.dart';
import 'lexeme_details.dart';

/// A saved entry: curated details, where it was met, review state,
/// personal note, collections and ownership actions.
class WordDetailScreen extends ConsumerWidget {
  const WordDetailScreen({super.key, required this.entryId});
  final String entryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(entryDetailsProvider(entryId));
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton()),
      body: AsyncView<EntryDetails?>(
        value: details,
        onRetry: () => ref.invalidate(entryDetailsProvider(entryId)),
        builder: (d) => d == null ? const ErrorState(message: 'Bu kelime artık defterinde değil.') : _Body(d: d),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.d});
  final EntryDetails d;

  String _due(CardState s, DateTime now) {
    if (s.lastReviewedAt == null) return 'henüz tekrar edilmedi';
    final diff = s.dueAt.difference(now);
    if (diff.isNegative) return 'şimdi';
    if (diff.inHours < 24) return '${diff.inHours < 1 ? 'bir saatten az' : '${diff.inHours} saat'} sonra';
    return '${diff.inDays} gün sonra';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = d.entry;
    final p = context.palette;
    final now = ref.watch(clockProvider)();
    final repo = ref.read(vocabRepositoryProvider);
    final collections = ref.watch(collectionsProvider).valueOrNull ?? const [];
    final lemma = e.article != null && e.headword.startsWith('${e.article} ') ? e.headword.substring(e.article!.length + 1) : e.headword;
    final scenario = d.lexeme == null
        ? null
        : ref.watch(contentProvider).scenarios.where((s) => s.vocab.contains(d.lexeme!.id)).firstOrNull;

    return ListView(
      padding: pagePadding,
      children: [
        PageWidth(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Headword(lemma: lemma, article: e.article, style: context.text.displaySmall!.copyWith(fontFamily: 'Literata'))),
              SpeakButton(e.headword, size: 28),
            ]),
            if (e.plural != null && e.plural != '—') Text('Çoğul: ${e.plural}', style: context.text.bodyMedium!.copyWith(color: p.inkMuted)),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _editText(context, title: 'Anlamı düzenle', initial: e.meaningTr, onSave: (v) async {
                await repo.updateMeaning(e.id, v);
                ref.bumpData();
              }),
              child: Row(children: [
                Expanded(child: Text(e.meaningTr, style: context.text.titleLarge)),
                Icon(Icons.edit_outlined, size: 18, color: p.inkMuted, semanticLabel: 'Anlamı düzenle'),
              ]),
            ),
            const SizedBox(height: 16),
            AppCard(
              color: p.surfaceAlt,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                  Pill(e.status.labelTr),
                  TextButton(
                    onPressed: () async {
                      await repo.setPaused(e.id, !e.paused);
                      ref.bumpData();
                    },
                    child: Text(e.paused ? 'Tekrara al' : 'Sonraya sakla'),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(e.status.explanationTr, style: context.text.bodyMedium),
                const SizedBox(height: 8),
                for (final c in d.cards)
                  Text(
                    '${switch (c.type) { CardType.recognition => 'Tanıma', CardType.production => 'Üretme (yazarak)', CardType.article => 'Artikel' }}: sıradaki tekrar ${_due(c.state, now)}${c.state.lapses > 0 ? ' · ${c.state.lapses} kez unutuldu' : ''}',
                    style: context.text.bodySmall,
                  ),
                if (!d.cards.any((c) => c.type == CardType.production) && !e.paused)
                  Text('Üretme kartı, kelimeyi ipucusuz tanıdığında açılır.', style: context.text.bodySmall),
                const SizedBox(height: 4),
                Text('Durum tahminidir; tekrar geçmişine göre hesaplanır.', style: context.text.labelSmall),
              ]),
            ),
            const SectionTitle('Nerede karşılaştın'),
            if (d.contexts.isEmpty)
              Text('Bağlam kaydedilmemiş.', style: context.text.bodySmall)
            else
              for (final c in d.contexts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    onTap: c.route == null ? null : () => context.push(c.route!),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${c.type.labelTr}${c.title != null ? ' · ${c.title}' : ''}', style: context.text.labelSmall),
                      if (c.sentence.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(c.sentence, style: context.reading.copyWith(fontSize: 16)),
                      ],
                      if (c.sentenceTr != null) Text(c.sentenceTr!, style: context.text.bodySmall),
                    ]),
                  ),
                ),
            if (d.lexeme != null) ...[
              const SectionTitle('Ayrıntılar'),
              LexemeDetails(lexeme: d.lexeme!),
            ],
            const SectionTitle('Kişisel not'),
            AppCard(
              onTap: () => _editText(context, title: 'Not', initial: e.note ?? '', onSave: (v) async {
                await repo.updateNote(e.id, v);
                ref.bumpData();
              }),
              child: Text(e.note ?? 'Not eklemek için dokun (ör. bir hatırlatma ya da kendi örneğin).', style: e.note == null ? context.text.bodySmall : context.text.bodyLarge),
            ),
            const SectionTitle('Koleksiyonlar'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in collections)
                Tag(
                  c.name,
                  icon: d.collections.contains(c.id) ? Icons.check_rounded : null,
                  selected: d.collections.contains(c.id),
                  onTap: () async {
                    await repo.setInCollection(c.id, e.id, !d.collections.contains(c.id));
                    ref.bumpData();
                  },
                ),
              Tag('Yeni koleksiyon', icon: Icons.add_rounded, onTap: () => _editText(context, title: 'Koleksiyon adı', initial: '', onSave: (v) async {
                    if (v.trim().isEmpty) return;
                    final id = await repo.createCollection(v);
                    await repo.setInCollection(id, e.id, true);
                    ref.bumpData();
                  })),
            ]),
            if (scenario != null) ...[
              const SectionTitle('Kullanarak öğren'),
              AppCard(
                onTap: () => context.push('/scenario/${scenario.id}?focus=${e.id}'),
                child: Row(children: [
                  Icon(Icons.forum_rounded, color: p.accent),
                  const SizedBox(width: 12),
                  Expanded(child: Text('"${e.headword}" ifadesini bir konuşmada kullan: ${scenario.titleTr}', style: context.text.titleSmall)),
                ]),
              ),
            ],
            const SizedBox(height: 28),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: p.danger),
              onPressed: () async {
                final ok = await confirm(context,
                    title: 'Kelimeyi sil?', message: '"${e.headword}" bağlamları ve tekrar geçmişiyle birlikte silinecek. Bu geri alınamaz.', confirmLabel: 'Sil', destructive: true);
                if (!ok) return;
                await repo.delete(e.id);
                ref.bumpData();
                if (context.mounted) closeOrHome(context);
              },
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Kelimeyi sil'),
            ),
          ]),
        ),
      ],
    );
  }
}

Future<void> _editText(BuildContext context, {required String title, required String initial, required Future<void> Function(String v) onSave}) async {
  final c = TextEditingController(text: initial);
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: Text(title),
      content: TextField(controller: c, autofocus: true, maxLines: 4, minLines: 1),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Kaydet')),
      ],
    ),
  );
  if (ok == true) await onSave(c.text);
  c.dispose();
}

/// A curated lexeme that may or may not be saved yet.
class LexemeDetailScreen extends ConsumerWidget {
  const LexemeDetailScreen({super.key, required this.lexemeId});
  final String lexemeId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(contentProvider).lexicon.byId(lexemeId);
    if (l == null) return Scaffold(appBar: AppBar(leading: const BackOrHomeButton()), body: const ErrorState(message: 'Bu kelime sözlükte yok.'));
    final saved = ref.watch(savedLexemeIdsProvider).valueOrNull?.contains(l.id) ?? false;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton()),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Headword(lemma: l.lemma, article: l.article, style: context.text.displaySmall!.copyWith(fontFamily: 'Literata'))),
                SpeakButton(l.headword, size: 28),
              ]),
              const SizedBox(height: 6),
              Text(l.tr, style: context.text.titleLarge),
              const SizedBox(height: 16),
              if (saved)
                OutlinedButton.icon(
                  onPressed: () async {
                    final e = await ref.read(vocabRepositoryProvider).entryByLexeme(l.id);
                    if (e != null && context.mounted) context.pushReplacement('/word/${e.id}');
                  },
                  icon: Icon(Icons.bookmark_rounded, color: context.palette.success),
                  label: const Text('Defterinde · aç'),
                )
              else
                FilledButton.icon(
                  onPressed: () async {
                    await saveLexeme(ref, l, null);
                    if (context.mounted) showToast(context, 'Kelime defterine eklendi');
                  },
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Kaydet'),
                ),
              const SizedBox(height: 16),
              LexemeDetails(lexeme: l),
            ]),
          ),
        ],
      ),
    );
  }
}
