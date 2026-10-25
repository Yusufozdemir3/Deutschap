import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/lesson.dart';
import '../../../content/models/lexeme.dart';
import '../../../ui/widgets.dart';
import '../../vocabulary/application/vocab_providers.dart';
import '../../vocabulary/domain/vocab_entry.dart';
import '../application/drill_words.dart';
import '../domain/vocab_drill.dart';

final weakLexemeIdsProvider = FutureProvider<List<String>>((ref) {
  ref.watch(dataRevisionProvider);
  return weakLexemeIds(ref.watch(progressRepositoryProvider));
});

final _collectionWordsProvider = FutureProvider.family<List<String>, String>((ref, id) {
  ref.watch(dataRevisionProvider);
  return ref.watch(vocabRepositoryProvider).collectionLexemeIds(id);
});

/// Chooses what to practise: a word source, an exercise type and a size.
class DrillScreen extends ConsumerStatefulWidget {
  const DrillScreen({super.key, this.initialSource});
  final String? initialSource;
  @override
  ConsumerState<DrillScreen> createState() => _DrillScreenState();
}

class _DrillScreenState extends ConsumerState<DrillScreen> {
  String? _source;
  DrillMode _mode = DrillMode.mixed;
  int _size = 10;

  @override
  void initState() {
    super.initState();
    _source = widget.initialSource;
  }

  /// Words a source offers, without loading them in order (just counts).
  List<Lexeme> _words(String source, Set<String> saved, List<String> weak) {
    final content = ref.read(contentProvider);
    final lex = content.lexicon;
    if (source == 'saved') return saved.map(lex.byId).whereType<Lexeme>().toList();
    if (source == 'weak') return weak.map(lex.byId).whereType<Lexeme>().toList();
    if (source.startsWith('collection:')) {
      final ids = ref.watch(_collectionWordsProvider(source.substring('collection:'.length))).valueOrNull ?? const <String>[];
      return ids.map(lex.byId).whereType<Lexeme>().toList();
    }
    final i = source.indexOf(':');
    final kind = i < 0 ? source : source.substring(0, i);
    final value = i < 0 ? '' : source.substring(i + 1);
    return switch (kind) {
      'level' => lex.all.where((l) => l.cefr == value).toList(),
      'tag' => lex.all.where((l) => l.tags.contains(value)).toList(),
      'unit' => {for (final l in content.unit(value)?.lessons ?? const <Lesson>[]) ...l.vocab}.map(lex.byId).whereType<Lexeme>().toList(),
      _ => lex.all.toList(),
    };
  }

  @override
  Widget build(BuildContext context) {
    final content = ref.watch(contentProvider);
    final saved = ref.watch(savedLexemeIdsProvider).valueOrNull ?? const <String>{};
    final weak = ref.watch(weakLexemeIdsProvider).valueOrNull ?? const <String>[];
    final collections = ref.watch(collectionsProvider).valueOrNull ?? const <CollectionInfo>[];
    final source = _source ?? (saved.length >= 4 ? 'saved' : 'level:A1');
    final gen = VocabDrillGenerator(content.lexicon);
    final words = _words(source, saved, weak);
    final usable = words.where((w) => gen.supports(w, _mode)).length;
    final p = context.palette;

    final tags = <String, int>{};
    for (final l in content.lexicon.all) {
      for (final t in l.tags) {
        if (drillTagLabels.containsKey(t)) tags[t] = (tags[t] ?? 0) + 1;
      }
    }
    final perLevel = <String, int>{};
    for (final l in content.lexicon.all) {
      perLevel[l.cefr] = (perLevel[l.cefr] ?? 0) + 1;
    }
    final levels = [for (final e in perLevel.entries) if (e.value >= 4) e.key]..sort();

    Widget sourceTag(String id, String label, {IconData? icon, int? count}) => Tag(
          count == null ? label : '$label ($count)',
          icon: icon,
          selected: source == id,
          onTap: () => setState(() => _source = id),
        );

    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Kelime antrenmanı')),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Kısa, odaklı turlar: tanıma, dinleme, yazma ve cümlede kullanma. '
                  'Yanlış yaptığın kelimeler "Zorlandıkların" listesinde toplanır.', style: context.text.bodySmall),
              const SectionTitle('Hangi kelimeler?'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                sourceTag('saved', 'Kaydettiklerim', icon: Icons.bookmark_rounded, count: saved.length),
                sourceTag('weak', 'Zorlandıkların', icon: Icons.priority_high_rounded, count: weak.length),
                for (final lv in levels) sourceTag('level:$lv', 'Tüm $lv kelimeleri', icon: Icons.school_outlined),
              ]),
              if (collections.any((c) => c.count > 0)) ...[
                const SizedBox(height: 12),
                Text('Koleksiyonların', style: context.text.labelMedium),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final c in collections)
                    if (c.count > 0) sourceTag('collection:${c.id}', c.name, icon: Icons.collections_bookmark_outlined, count: c.count),
                ]),
              ],
              const SizedBox(height: 12),
              Text('Konuya göre', style: context.text.labelMedium),
              const SizedBox(height: 6),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final t in (tags.keys.toList()..sort((a, b) => drillTagLabels[a]!.compareTo(drillTagLabels[b]!))))
                  if (tags[t]! >= 4) sourceTag('tag:$t', drillTagLabels[t]!, count: tags[t]),
              ]),
              const SizedBox(height: 12),
              Text('Üniteye göre', style: context.text.labelMedium),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                key: ValueKey(source),
                initialValue: source.startsWith('unit:') ? source : null,
                isExpanded: true,
                hint: const Text('Bir ünite seç'),
                items: [
                  for (final path in content.paths)
                    for (final u in path.units)
                      if (u.lessons.isNotEmpty)
                        DropdownMenuItem(value: 'unit:${u.id}', child: Text('${path.level} · Ünite ${u.number}: ${u.titleDe}', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _source = v),
              ),
              const SectionTitle('Alıştırma türü'),
              for (final m in DrillMode.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    onTap: () => setState(() => _mode = m),
                    color: _mode == m ? p.accentSoft : null,
                    borderColor: _mode == m ? p.accent : null,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    semanticLabel: '${m.labelTr}: ${m.descriptionTr}${_mode == m ? ', seçili' : ''}',
                    child: Row(children: [
                      Icon(_modeIcon(m), color: _mode == m ? p.accent : p.inkMuted),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m.labelTr, style: context.text.titleSmall),
                          Text(m.descriptionTr, style: context.text.bodySmall),
                        ]),
                      ),
                      if (_mode == m) Icon(Icons.check_rounded, color: p.accent),
                    ]),
                  ),
                ),
              const SectionTitle('Tur uzunluğu'),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 5, label: Text('5')),
                  ButtonSegment(value: 10, label: Text('10')),
                  ButtonSegment(value: 20, label: Text('20')),
                ],
                selected: {_size},
                onSelectionChanged: (s) => setState(() => _size = s.first),
              ),
              const SizedBox(height: 20),
              Text(
                usable == 0
                    ? 'Bu seçimde bu alıştırma türüne uygun kelime yok.'
                    : 'Bu seçimde $usable uygun kelime var${usable < _size ? '; tur $usable kelimeyle yapılacak' : ''}.',
                style: context.text.bodySmall,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: usable == 0
                    ? null
                    : () => context.push('/drill/run?${DrillSpec(source: source, mode: _mode, size: _size).query}'),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('Başla'),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  static IconData _modeIcon(DrillMode m) => switch (m) {
        DrillMode.mixed => Icons.shuffle_rounded,
        DrillMode.meaning => Icons.translate_rounded,
        DrillMode.reverse => Icons.swap_horiz_rounded,
        DrillMode.article => Icons.label_outline_rounded,
        DrillMode.plural => Icons.filter_none_rounded,
        DrillMode.spell => Icons.keyboard_rounded,
        DrillMode.listen => Icons.hearing_rounded,
        DrillMode.context => Icons.short_text_rounded,
        DrillMode.conjugate => Icons.person_outline_rounded,
        DrillMode.perfekt => Icons.history_rounded,
        DrillMode.match => Icons.join_inner_rounded,
      };
}
