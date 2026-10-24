import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/lexeme.dart';
import '../../../ui/widgets.dart';

/// Full curated information about a lexeme. Only fields that exist are
/// shown, so a particle does not get empty "plural" rows.
class LexemeDetails extends ConsumerWidget {
  const LexemeDetails({super.key, required this.lexeme});
  final Lexeme lexeme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = lexeme;
    final p = context.palette;
    final lexicon = ref.watch(contentProvider).lexicon;
    final showEn = ref.watch(profileProvider).valueOrNull?.showEnglish ?? false;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 120, child: Text(k, style: context.text.bodySmall)),
            Expanded(child: Text(v, style: context.text.bodyMedium!.copyWith(fontFamily: 'Literata'))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          row('Tür', '${l.pos.labelTr}${l.register == Register.formal ? ' · resmî' : (l.register == Register.informal ? ' · samimi' : '')}'),
          if (l.isNoun && l.article != null) row('Artikel', '${l.article} (${switch (l.article) { 'der' => 'eril', 'die' => 'dişil', _ => 'nötr' }})'),
          if (l.isNoun && l.plural != null) row('Çoğul', l.plural == '—' ? 'genelde çoğul kullanılmaz' : l.plural!),
          if (l.verb case final v?) ...[
            row('er/sie/es', v.present3),
            if (v.participle != '—') row('Perfekt', '${v.auxiliaryShort} ${v.participle} (${v.auxiliary})'),
            if (v.separablePrefix != null) row('Ayrılabilen', 'ön ek "${v.separablePrefix}" cümle sonuna gider'),
            if (v.pattern != null) row('Kalıp', v.pattern!),
          ],
          row('Seviye', l.cefr),
          if (showEn && l.en != null) row('English', l.en!),
        ]),
      ),
      if (l.verb?.presentForms.isNotEmpty ?? false) ...[
        const SectionTitle('Şimdiki zaman'),
        AppCard(
          child: Column(children: [
            for (final e in l.verb!.presentForms.entries) row(e.key, e.value),
          ]),
        ),
      ],
      if (l.noteTr != null) ...[
        const SectionTitle('Not'),
        Text(l.noteTr!, style: context.text.bodyLarge),
      ],
      if (l.commonMistakeTr != null) ...[
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: p.dangerSoft, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Dikkat', style: context.text.titleSmall),
            const SizedBox(height: 4),
            Text(l.commonMistakeTr!, style: context.text.bodyMedium),
          ]),
        ),
      ],
      if (l.examples.isNotEmpty) ...[
        const SectionTitle('Örnekler'),
        for (final e in l.examples)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e.de, style: context.reading.copyWith(fontSize: 17)),
                  Text(e.tr, style: context.text.bodySmall),
                ]),
              ),
              SpeakButton(e.de, size: 20),
            ]),
          ),
      ],
      if (l.collocations.isNotEmpty) ...[
        const SectionTitle('Sık birlikte kullanılır'),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final c in l.collocations) Tag(c, textStyle: context.reading.copyWith(fontSize: 15))]),
      ],
      if (l.related.isNotEmpty) ...[
        const SectionTitle('İlgili kelimeler'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final r in l.related)
            if (lexicon.byId(r) case final rl?) Tag(rl.headword, onTap: () => context.push('/lexeme/${rl.id}')),
        ]),
      ],
    ]);
  }
}
