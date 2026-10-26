import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../domain/review_items.dart';

const _marksKey = 'content_review';

final reviewItemsProvider = Provider<List<ReviewItem>>((ref) => collectReviewItems(ref.watch(contentProvider)));

final reviewMarksProvider = FutureProvider<Map<String, ReviewMark>>((ref) async {
  ref.watch(dataRevisionProvider);
  final j = await ref.watch(kvStoreProvider).getJson(_marksKey);
  return {for (final e in j.entries) e.key: ReviewMark.fromJson((e.value as Map).cast<String, dynamic>())};
});

Future<void> _setMark(WidgetRef ref, String id, ReviewMark? mark) async {
  final kv = ref.read(kvStoreProvider);
  final j = await kv.getJson(_marksKey);
  if (mark == null) {
    j.remove(id);
  } else {
    j[id] = mark.toJson();
  }
  await kv.setJson(_marksKey, j);
  ref.bumpData();
}

enum _Filter { open, issues, all }

/// For a German-speaking reviewer: go through every sentence the app
/// teaches, confirm it or flag it with a note, and export the flags.
class ContentReviewScreen extends ConsumerStatefulWidget {
  const ContentReviewScreen({super.key});
  @override
  ConsumerState<ContentReviewScreen> createState() => _ContentReviewScreenState();
}

class _ContentReviewScreenState extends ConsumerState<ContentReviewScreen> {
  ReviewArea _area = ReviewArea.lessons;
  _Filter _filter = _Filter.open;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(reviewItemsProvider);
    final marks = ref.watch(reviewMarksProvider).valueOrNull ?? const {};
    final inArea = items.where((i) => i.area == _area).toList();
    final q = _query.trim().toLowerCase();
    final shown = [
      for (final i in inArea)
        if ((q.isEmpty || i.de.toLowerCase().contains(q) || (i.tr?.toLowerCase().contains(q) ?? false) || i.where.toLowerCase().contains(q)) &&
            switch (_filter) {
              _Filter.open => marks[i.id] == null,
              _Filter.issues => marks[i.id]?.verdict == ReviewVerdict.issue,
              _Filter.all => true,
            })
          i,
    ];
    final checked = inArea.where((i) => marks.containsKey(i.id)).length;
    final issues = marks.values.where((m) => m.verdict == ReviewVerdict.issue).length;

    return Scaffold(
      appBar: AppBar(
        leading: const BackOrHomeButton(),
        title: const Text('İçerik denetimi'),
        actions: [
          IconButton(
            tooltip: 'Sorunları dışa aktar',
            onPressed: issues == 0 ? null : () => _export(items, marks),
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: Column(children: [
        PageWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Her cümleyi "doğru" ya da "sorun var" diye işaretle. İşaretler bu cihazda (ve yedekte) saklanır; sorunları tablo olarak dışa aktarabilirsin.', style: context.text.bodySmall),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final a in ReviewArea.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(label: Text(a.labelTr), selected: _area == a, onSelected: (_) => setState(() => _area = a)),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(isDense: true, prefixIcon: Icon(Icons.search_rounded), hintText: 'Ara (Almanca, Türkçe, yer)'),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<_Filter>(
                  value: _filter,
                  onChanged: (f) => setState(() => _filter = f!),
                  items: const [
                    DropdownMenuItem(value: _Filter.open, child: Text('Bakılmamış')),
                    DropdownMenuItem(value: _Filter.issues, child: Text('Sorunlu')),
                    DropdownMenuItem(value: _Filter.all, child: Text('Hepsi')),
                  ],
                ),
              ]),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: inArea.isEmpty ? 0 : checked / inArea.length),
              const SizedBox(height: 4),
              Text('${_area.labelTr}: $checked / ${inArea.length} kontrol edildi · toplam $issues sorun', style: context.text.bodySmall),
            ]),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? const EmptyState(icon: Icons.task_alt_rounded, title: 'Burada gösterilecek cümle yok', message: 'Başka bir alan ya da filtre seç.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: shown.length,
                  itemBuilder: (_, i) => PageWidth(child: _ItemCard(item: shown[i], mark: marks[shown[i].id])),
                ),
        ),
      ]),
    );
  }

  Future<void> _export(List<ReviewItem> items, Map<String, ReviewMark> marks) async {
    final tsv = reviewReportTsv(items, marks);
    final now = ref.read(contentProvider).version;
    try {
      await FilePicker.saveFile(
        fileName: 'deutschap-icerik-sorunlari-$now.tsv',
        bytes: Uint8List.fromList(utf8.encode(tsv)),
        mimeType: 'text/tab-separated-values',
        dialogTitle: 'Sorun listesini kaydet',
      );
      if (mounted && kIsWeb) showToast(context, 'Sorun listesi indirildi');
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: tsv));
      if (mounted) showToast(context, 'Sorun listesi panoya kopyalandı (tablo programına yapıştırılabilir)');
    }
  }
}

class _ItemCard extends ConsumerWidget {
  const _ItemCard({required this.item, required this.mark});
  final ReviewItem item;
  final ReviewMark? mark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final m = mark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        borderColor: switch (m?.verdict) { ReviewVerdict.ok => p.success, ReviewVerdict.issue => p.danger, null => null },
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.where, style: context.text.labelSmall!.copyWith(color: p.inkMuted)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: SelectableText(item.de, style: context.text.titleMedium!.copyWith(fontFamily: context.serif))),
            SpeakButton(item.de, size: 20),
          ]),
          if (item.tr != null) Text(item.tr!, style: context.text.bodyMedium!.copyWith(color: p.inkMuted)),
          if (item.extra != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(item.extra!, style: context.text.bodySmall)),
          if (m?.note != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Not: ${m!.note}', style: context.text.bodySmall!.copyWith(color: p.danger))),
          Wrap(alignment: WrapAlignment.end, children: [
            if (m != null) TextButton(onPressed: () => _setMark(ref, item.id, null), child: const Text('Geri al')),
            TextButton.icon(
              onPressed: () => _flag(context, ref),
              icon: Icon(Icons.flag_outlined, color: p.danger),
              label: Text(m?.verdict == ReviewVerdict.issue ? 'Notu düzenle' : 'Sorun var'),
            ),
            if (m?.verdict != ReviewVerdict.ok)
              TextButton.icon(
                onPressed: () => _setMark(ref, item.id, const ReviewMark(ReviewVerdict.ok)),
                icon: Icon(Icons.check_rounded, color: p.success),
                label: const Text('Doğru'),
              ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _flag(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController(text: mark?.note ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Sorun nedir?'),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'ör. "Termin vereinbaren" daha doğal; çeviri eksik'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('İşaretle')),
        ],
      ),
    );
    final note = c.text.trim();
    c.dispose();
    if (ok == true) await _setMark(ref, item.id, ReviewMark(ReviewVerdict.issue, note: note.isEmpty ? null : note));
  }
}
