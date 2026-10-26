import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';

/// All word families: a root, its members and how they are built.
class FamiliesScreen extends ConsumerWidget {
  const FamiliesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(contentProvider);
    final lexicon = content.lexicon;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Kelime aileleri')),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Aynı kökten gelen kelimeleri birlikte öğrenmek, birini bilince diğerlerini tahmin etmeni sağlar. '
                  'Ön ekler (ab-, an-, um-, ver-) ve son ekler (-ung, -er, -heit) nasıl kelime türettiğine dikkat et.', style: context.text.bodySmall),
              const SizedBox(height: 8),
              for (final f in content.families)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(f.root, style: context.text.titleMedium!.copyWith(fontFamily: 'Literata')),
                            Text(f.tr, style: context.text.bodySmall),
                          ]),
                        ),
                        TextButton.icon(
                          onPressed: () => context.push('/drill/run?src=${Uri.encodeComponent('family:${f.id}')}&mode=mixed&n=10'),
                          icon: const Icon(Icons.fitness_center_rounded, size: 18),
                          label: const Text('Alıştır'),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 8, children: [
                        for (final m in f.members)
                          if (lexicon.byId(m) case final l?) Tag('${l.headword} · ${l.tr}', onTap: () => context.push('/lexeme/${l.id}')),
                      ]),
                      const SizedBox(height: 8),
                      Text(f.noteTr, style: context.text.bodySmall!.copyWith(color: context.palette.inkMuted)),
                    ]),
                  ),
                ),
            ]),
          ),
        ],
      ),
    );
  }
}
