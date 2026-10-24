import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import 'grammar_view.dart';

class GrammarScreen extends ConsumerWidget {
  const GrammarScreen({super.key, required this.conceptId});
  final String conceptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grammar = ref.watch(contentProvider).grammar;
    final c = grammar[conceptId];
    if (c == null) {
      return Scaffold(appBar: AppBar(leading: const BackOrHomeButton()), body: const ErrorState(message: 'Bu konu bulunamadı.'));
    }
    final prereq = [for (final r in c.requires) ?grammar[r]];
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton()),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              GrammarConceptView(concept: c),
              if (prereq.isNotEmpty) ...[
                const SectionTitle('Önce bunlara bakmak isteyebilirsin'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final g in prereq) ActionChip(label: Text(g.titleTr), onPressed: () => context.push('/grammar/${g.id}')),
                ]),
              ],
              const SizedBox(height: 16),
              Text('Sürüm 0.1: bu açıklamalar otomatik kontrollerden geçti ama henüz bir Almanca öğretmeni tarafından gözden geçirilmedi. Bölgesel kullanım farkları olabilir.', style: context.text.bodySmall),
            ]),
          ),
        ],
      ),
    );
  }
}
