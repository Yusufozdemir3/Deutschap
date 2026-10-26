import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/lexeme.dart';
import '../../../learning/text/tokenizer.dart';
import '../../../ui/widgets.dart';
import '../application/vocab_providers.dart';

/// Browse and search every word the app knows (not only saved ones).
class DictionaryScreen extends ConsumerStatefulWidget {
  const DictionaryScreen({super.key});
  @override
  ConsumerState<DictionaryScreen> createState() => _DictionaryScreenState();
}

class _DictionaryScreenState extends ConsumerState<DictionaryScreen> {
  final _search = TextEditingController();
  String _query = '';
  String? _level;
  PartOfSpeech? _pos;
  bool _onlyUnsaved = false;
  int _shown = 60;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<Lexeme> _filter(Iterable<Lexeme> all, Set<String> saved) {
    final q = fold(_query.trim());
    final out = [
      for (final l in all)
        if ((_level == null || l.cefr == _level) &&
            (_pos == null || l.pos == _pos) &&
            (!_onlyUnsaved || !saved.contains(l.id)) &&
            (q.isEmpty || fold(l.lemma).contains(q) || fold(l.tr).contains(q) || (l.en?.toLowerCase().contains(q) ?? false) || l.forms.any((f) => fold(f).startsWith(q))))
          l,
    ];
    // Exact and prefix matches first, then alphabetical.
    int rank(Lexeme l) {
      if (q.isEmpty) return 2;
      final lemma = fold(l.lemma);
      if (lemma == q) return 0;
      if (lemma.startsWith(q)) return 1;
      return 2;
    }

    out.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      return r != 0 ? r : fold(a.lemma).compareTo(fold(b.lemma));
    });
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final content = ref.watch(contentProvider);
    final saved = ref.watch(savedLexemeIdsProvider).valueOrNull ?? const <String>{};
    final all = content.lexicon.all;
    final levels = {for (final l in all) l.cefr}.toList()..sort();
    final results = _filter(all, saved);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        leading: const BackOrHomeButton(),
        title: const Text('Sözlük'),
        actions: [TextButton.icon(onPressed: () => context.push('/families'), icon: const Icon(Icons.account_tree_outlined), label: const Text('Aileler'))],
      ),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              TextField(
                controller: _search,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: 'Almanca ya da Türkçe ara (${all.length} kelime)',
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Temizle',
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () => setState(() {
                            _search.clear();
                            _query = '';
                            _shown = 60;
                          }),
                        ),
                ),
                onChanged: (v) => setState(() {
                  _query = v;
                  _shown = 60;
                }),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, children: [
                Tag('Hepsi', selected: _level == null, onTap: () => setState(() => _level = null)),
                for (final lv in levels) Tag(lv, selected: _level == lv, onTap: () => setState(() => _level = _level == lv ? null : lv)),
                Tag('Kaydedilmemiş', icon: Icons.bookmark_border_rounded, selected: _onlyUnsaved, onTap: () => setState(() => _onlyUnsaved = !_onlyUnsaved)),
              ]),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final pos in const [PartOfSpeech.noun, PartOfSpeech.verb, PartOfSpeech.adjective, PartOfSpeech.adverb, PartOfSpeech.expression])
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(pos.labelTr),
                        selected: _pos == pos,
                        onSelected: (_) => setState(() => _pos = _pos == pos ? null : pos),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              Text('${results.length} sonuç', style: context.text.labelSmall),
              const SizedBox(height: 4),
              if (results.isEmpty)
                const EmptyState(icon: Icons.search_off_rounded, title: 'Sonuç yok', message: 'Başka bir yazım ya da filtre dene. Türkçe anlamla da arayabilirsin.')
              else
                for (final l in results.take(_shown))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: AppCard(
                      onTap: () => context.push('/lexeme/${l.id}'),
                      padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Headword(lemma: l.lemma, article: l.article, style: context.text.titleSmall),
                            Text(l.tr, style: context.text.bodyMedium),
                            Text('${l.pos.labelTr} · ${l.cefr}', style: context.text.labelSmall),
                          ]),
                        ),
                        SpeakButton(l.headword, size: 20),
                        saved.contains(l.id)
                            ? Padding(padding: const EdgeInsets.all(10), child: Icon(Icons.bookmark_added_rounded, color: p.success, semanticLabel: 'Kayıtlı'))
                            : IconButton(
                                tooltip: 'Kelime defterine kaydet',
                                icon: const Icon(Icons.bookmark_add_outlined),
                                onPressed: () async {
                                  await saveLexeme(ref, l, null);
                                  if (context.mounted) showToast(context, '${l.headword} kelime defterine eklendi');
                                },
                              ),
                      ]),
                    ),
                  ),
              if (results.length > _shown)
                Center(child: TextButton(onPressed: () => setState(() => _shown += 60), child: Text('Daha fazla göster (${results.length - _shown} kaldı)'))),
            ]),
          ),
        ],
      ),
    );
  }
}
