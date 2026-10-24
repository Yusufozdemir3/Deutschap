import 'package:flutter/material.dart';

import '../../../app/theme/app_theme.dart';
import '../../../content/models/grammar.dart';
import '../../../ui/widgets.dart';

/// Several ways into one concept: rule, pattern table, examples, a
/// Turkish comparison and a typical mistake.
class GrammarConceptView extends StatelessWidget {
  const GrammarConceptView({super.key, required this.concept, this.compact = false});
  final GrammarConcept concept;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = concept;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(c.titleTr, style: context.text.headlineSmall),
        const SizedBox(height: 4),
        Text('${c.level} · dil bilgisi', style: context.text.labelSmall),
        const SizedBox(height: 14),
        Text(c.ruleTr, style: context.text.bodyLarge),
        if (c.table.isNotEmpty) ...[
          const SizedBox(height: 16),
          _PatternTable(rows: c.table),
        ],
        if (c.examples.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Örnekler', style: context.text.titleSmall),
          const SizedBox(height: 6),
          for (final e in c.examples)
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
        if (c.turkishCompareTr != null && !compact) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Türkçeyle karşılaştır', style: context.text.titleSmall),
              const SizedBox(height: 4),
              Text(c.turkishCompareTr!, style: context.text.bodyMedium),
            ]),
          ),
        ],
        if (c.mistake != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: p.dangerSoft, borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Sık yapılan hata', style: context.text.titleSmall),
              const SizedBox(height: 6),
              Text.rich(TextSpan(children: [
                TextSpan(text: '✗ ', style: TextStyle(color: p.danger)),
                TextSpan(text: c.mistake!.wrong, style: const TextStyle(decoration: TextDecoration.lineThrough)),
              ]), style: context.reading.copyWith(fontSize: 16), semanticsLabel: 'Yanlış: ${c.mistake!.wrong}'),
              Text.rich(TextSpan(children: [
                TextSpan(text: '✓ ', style: TextStyle(color: p.success)),
                TextSpan(text: c.mistake!.right),
              ]), style: context.reading.copyWith(fontSize: 16), semanticsLabel: 'Doğru: ${c.mistake!.right}'),
              const SizedBox(height: 4),
              Text(c.mistake!.explainTr, style: context.text.bodyMedium),
            ]),
          ),
        ],
      ],
    );
  }
}

class _PatternTable extends StatelessWidget {
  const _PatternTable({required this.rows});
  final List<List<String>> rows;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        decoration: BoxDecoration(border: Border.all(color: p.line), borderRadius: BorderRadius.circular(12)),
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          children: [
            for (var r = 0; r < rows.length; r++)
              TableRow(
                decoration: BoxDecoration(color: r == 0 ? p.surfaceAlt : null),
                children: [
                  for (final cell in rows[r])
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(cell, style: r == 0 ? context.text.labelMedium : context.text.bodyMedium!.copyWith(fontFamily: 'Literata')),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
