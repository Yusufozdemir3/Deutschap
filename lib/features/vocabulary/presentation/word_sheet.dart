import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/lexeme.dart';
import '../../../learning/text/lexicon.dart';
import '../../../ui/german_text.dart';
import '../../../ui/widgets.dart';
import '../application/vocab_providers.dart';
import '../domain/vocab_entry.dart';

/// Opens the select-to-learn panel for a tapped word. [source] describes
/// where the text came from so the saved entry keeps its context.
///
/// [sentenceTr] is the curated translation of the whole tapped line. When
/// the line has several sentences it is shown as the line's translation
/// and not stored as the translation of the single saved sentence.
Future<void> showWordSheet(
  BuildContext context, {
  required WordTap tap,
  required SourceContext source,
  String? sentenceTr,
}) {
  final singleSentence = RegExp(r'[.!?]+(\s|$)').allMatches(tap.lineText.trim()).length <= 1;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (context, scroll) => _WordSheet(tap: tap, source: source, sentenceTr: sentenceTr, lineOnly: !singleSentence, scroll: scroll),
    ),
  );
}

class _WordSheet extends ConsumerWidget {
  const _WordSheet({required this.tap, required this.source, required this.scroll, this.sentenceTr, this.lineOnly = false});
  final WordTap tap;
  final SourceContext source;
  final String? sentenceTr;
  final bool lineOnly;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lexicon = ref.watch(contentProvider).lexicon;
    final lower = tap.sentenceWords.map((w) => w.toLowerCase()).toList();
    final phrases = lexicon.phrasesAt(tap.sentenceWords, tap.wordIndex);
    final lookup = lexicon.lookupWord(tap.surface, sentenceWords: lower, wordIndex: tap.wordIndex);
    final ctx = SourceContext(
      type: source.type,
      sourceId: source.sourceId,
      title: source.title,
      sentence: tap.sentence,
      sentenceTr: lineOnly ? null : sentenceTr,
    );
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      children: [
        Row(
          children: [
            Expanded(child: Text(tap.surface, style: context.text.headlineSmall!.copyWith(fontFamily: 'Literata'))),
            SpeakButton(tap.surface),
          ],
        ),
        if (lookup.isEmpty && phrases.isEmpty) _Unknown(tap: tap, context_: ctx),
        if (lookup.confidence == LookupConfidence.guess && lookup.lexemes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: FeedbackPanel(
              positive: true,
              neutral: true,
              title: 'Bu bir tahmin',
              body: '"${tap.surface}" büyük olasılıkla aşağıdaki kelimenin bir biçimi. Emin değiliz; bağlama göre kontrol et.',
            ),
          ),
        if (lookup.lexemes.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('Bu yazılışın birden fazla anlamı olabilir. Cümleye göre doğru olanı seç.', style: context.text.bodySmall),
          ),
        for (final m in phrases) ...[
          Text('Kalıp ifade', style: context.text.labelSmall),
          const SizedBox(height: 6),
          LexemeCard(lexeme: m.lexeme, context_: ctx),
          const SizedBox(height: 12),
        ],
        for (final l in lookup.lexemes) ...[
          LexemeCard(lexeme: l, context_: ctx),
          const SizedBox(height: 12),
        ],
        const SizedBox(height: 4),
        _SentenceBox(sentence: tap.sentence, sentenceTr: sentenceTr, lineOnly: lineOnly),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () async {
              final (_, existed) = await ref.read(vocabRepositoryProvider).saveSentence(
                    sentence: tap.sentence,
                    target: tap.surface,
                    sentenceTr: lineOnly ? null : sentenceTr,
                    context: ctx,
                  );
              ref.bumpData();
              if (context.mounted) showToast(context, existed ? 'Bu cümle zaten kayıtlı' : 'Cümle kaydedildi: tekrarda "${tap.surface}" boşluk olarak sorulacak');
            },
            icon: const Icon(Icons.format_quote_rounded),
            label: Text('Cümleyi kaydet ("${tap.surface}" boşluk olur)'),
          ),
        ),
      ],
    );
  }
}

class _SentenceBox extends StatelessWidget {
  const _SentenceBox({required this.sentence, this.sentenceTr, this.lineOnly = false});
  final String sentence;
  final String? sentenceTr;
  final bool lineOnly;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: context.palette.surfaceAlt, borderRadius: BorderRadius.circular(14)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Cümle', style: context.text.labelSmall)),
              SpeakButton(sentence, size: 20),
              SpeakButton(sentence, slow: true, size: 20),
            ]),
            Text(sentence, style: context.reading.copyWith(fontSize: 17)),
            const SizedBox(height: 6),
            if (lineOnly && sentenceTr != null) Text('Satırın tamamının çevirisi:', style: context.text.labelSmall),
            Text(
              sentenceTr ?? 'Bu cümlenin doğrulanmış bir çevirisi yok. Uydurma bir çeviri göstermiyoruz.',
              style: sentenceTr == null ? context.text.bodySmall : context.text.bodyMedium,
            ),
          ],
        ),
      );
}

/// Compact lexeme summary with save action. The full view is one tap away.
class LexemeCard extends ConsumerWidget {
  const LexemeCard({super.key, required this.lexeme, this.context_, this.showDetailsLink = true});
  final Lexeme lexeme;
  final SourceContext? context_;
  final bool showDetailsLink;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedLexemeIdsProvider).valueOrNull?.contains(lexeme.id) ?? false;
    final showEn = ref.watch(profileProvider).valueOrNull?.showEnglish ?? false;
    final l = lexeme;
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Headword(lemma: l.lemma, article: l.article, style: context.text.titleLarge),
                    const SizedBox(height: 2),
                    Text(_grammarLine(l), style: context.text.bodySmall),
                  ],
                ),
              ),
              SpeakButton(l.headword),
            ],
          ),
          const SizedBox(height: 8),
          Text(l.tr, style: context.text.bodyLarge!.semibold),
          if (showEn && l.en != null) Text(l.en!, style: context.text.bodySmall),
          if (l.noteTr != null) ...[const SizedBox(height: 6), Text(l.noteTr!, style: context.text.bodyMedium)],
          if (l.examples.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(l.examples.first.de, style: context.reading.copyWith(fontSize: 16)),
            Text(l.examples.first.tr, style: context.text.bodySmall),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (saved)
                OutlinedButton.icon(
                  onPressed: context_ == null
                      ? null
                      : () async {
                          await saveLexeme(ref, l, context_);
                          if (context.mounted) showToast(context, 'Yeni bağlam eklendi');
                        },
                  icon: Icon(Icons.bookmark_added_rounded, color: context.palette.success),
                  label: Text(context_ == null ? 'Kayıtlı' : 'Kayıtlı · bağlam ekle'),
                )
              else
                FilledButton.icon(
                  onPressed: () async {
                    await saveLexeme(ref, l, context_);
                    if (context.mounted) showToast(context, 'Kelime defterine eklendi${context_?.sentence.isNotEmpty == true ? ' · cümlesiyle birlikte' : ''}');
                  },
                  icon: const Icon(Icons.bookmark_add_outlined),
                  label: const Text('Kaydet'),
                ),
              if (showDetailsLink)
                TextButton(
                  onPressed: () {
                    Navigator.of(context).maybePop();
                    context.push('/lexeme/${l.id}');
                  },
                  child: const Text('Ayrıntılar'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String _grammarLine(Lexeme l) {
  final parts = <String>[l.pos.labelTr];
  if (l.isNoun) {
    if (l.plural != null) parts.add(l.plural == '—' ? 'çoğulu yaygın değil' : 'çoğul: ${l.plural}');
  }
  final v = l.verb;
  if (v != null) {
    parts.add('er/sie: ${v.present3}');
    if (v.participle != '—') parts.add('Perfekt: ${v.perfektExample}');
  }
  if (l.register == Register.formal) parts.add('resmî');
  if (l.register == Register.informal) parts.add('samimi');
  return parts.join(' · ');
}

class _Unknown extends ConsumerWidget {
  const _Unknown({required this.tap, required this.context_});
  final WordTap tap;
  final SourceContext context_;
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Bu kelime henüz Deutschap sözlüğünde yok.', style: context.text.titleSmall),
            const SizedBox(height: 4),
            Text('Yanlış bilgi vermemek için tahmin üretmiyoruz. İstersen kendi notunla kaydedebilirsin; cümlesi de saklanır.',
                style: context.text.bodySmall),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => showManualAddDialog(context, ref, headword: tap.surface, context_: context_),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Kendi anlamımla kaydet'),
            ),
          ],
        ),
      );
}

/// Manual entry form; used from the word sheet and the library.
Future<void> showManualAddDialog(BuildContext context, WidgetRef ref, {String headword = '', SourceContext? context_}) async {
  final word = TextEditingController(text: headword);
  final meaning = TextEditingController();
  String? article;
  final result = await showDialog<bool>(
    context: context,
    builder: (c) => StatefulBuilder(
      builder: (c, setState) => AlertDialog(
        title: const Text('Kelime ekle'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: word, decoration: const InputDecoration(labelText: 'Almanca (kelime veya ifade)'), textCapitalization: TextCapitalization.none),
              const SizedBox(height: 12),
              TextField(controller: meaning, decoration: const InputDecoration(labelText: 'Türkçe anlamı'), autofocus: headword.isNotEmpty),
              const SizedBox(height: 12),
              Align(alignment: Alignment.centerLeft, child: Text('İsimse artikel:', style: c.text.bodySmall)),
              const SizedBox(height: 6),
              SegmentedButton<String?>(
                segments: const [
                  ButtonSegment(value: null, label: Text('—')),
                  ButtonSegment(value: 'der', label: Text('der')),
                  ButtonSegment(value: 'die', label: Text('die')),
                  ButtonSegment(value: 'das', label: Text('das')),
                ],
                selected: {article},
                onSelectionChanged: (s) => setState(() => article = s.first),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Kaydet')),
        ],
      ),
    ),
  );
  if (result != true) return;
  final w = word.text.trim();
  final m = meaning.text.trim();
  if (w.isEmpty || m.isEmpty) {
    if (context.mounted) showToast(context, 'Kelime ve anlam gerekli.');
    return;
  }
  final isNoun = article != null;
  final head = isNoun && !w.startsWith('$article ') ? '$article ${w[0].toUpperCase()}${w.substring(1)}' : w;
  await ref.read(vocabRepositoryProvider).saveManual(
        headword: head,
        meaningTr: m,
        kind: isNoun ? 'noun' : 'expression',
        article: article,
        context: context_,
      );
  ref.bumpData();
  if (context.mounted) showToast(context, 'Kelime defterine eklendi');
}
