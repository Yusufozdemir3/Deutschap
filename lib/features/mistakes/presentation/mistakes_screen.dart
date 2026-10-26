import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/clock.dart';
import '../../../ui/widgets.dart';
import '../domain/mistake_book.dart';

/// Open mistakes of the last 60 days, newest and most repeated first.
final openMistakesProvider = FutureProvider<List<Mistake>>((ref) async {
  ref.watch(dataRevisionProvider);
  final repo = ref.watch(progressRepositoryProvider);
  final now = ref.watch(clockProvider)();
  return MistakeBook(ref.watch(contentProvider)).open(
    await repo.attempts(since: now.subtract(const Duration(days: 60))),
    await repo.conversations(limit: 50),
  );
});

class MistakesScreen extends ConsumerWidget {
  const MistakesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mistakes = ref.watch(openMistakesProvider);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Hata defteri')),
      body: AsyncView<List<Mistake>>(
        value: mistakes,
        onRetry: () => ref.invalidate(openMistakesProvider),
        builder: (list) => ListView(
          padding: pagePadding,
          children: [
            PageWidth(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Derslerde, kelime antrenmanında, dinlemede ve konuşmalarda yanlış yaptığın şeyler burada toplanır. '
                    'Bir soruyu sonradan doğru cevapladığında defterden çıkar.', style: context.text.bodySmall),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  const EmptyState(icon: Icons.check_circle_outline_rounded, title: 'Açık hatan yok', message: 'Son 60 günde düzeltilmemiş bir hatan yok. Hata yapmak öğrenmenin parçası – yaptığında burada göreceksin.')
                else ...[
                  AppCard(
                    color: p.accentSoft,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('${list.length} açık hata', style: context.text.titleMedium),
                      const SizedBox(height: 4),
                      Text('Kısa bir düzeltme turu en çok tekrar eden 12 hatayı yeniden sorar. Haftada bir kez yapmak yeterli.', style: context.text.bodySmall),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: list.any((m) => m.step != null) ? () => context.push('/mistakes/review') : null,
                        icon: const Icon(Icons.replay_rounded),
                        label: const Text('Düzeltme turunu başlat'),
                      ),
                    ]),
                  ),
                  for (final source in MistakeSource.values)
                    if (list.any((m) => m.source == source)) ...[
                      SectionTitle(source.labelTr),
                      for (final m in list.where((m) => m.source == source).take(30))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: AppCard(
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(m.titleTr, style: context.text.labelMedium)),
                                if (m.misses > 1) Pill('${m.misses} kez'),
                              ]),
                              const SizedBox(height: 4),
                              if (m.correction != null) ...[
                                Text(m.detail, style: context.reading.copyWith(fontSize: 16, decoration: TextDecoration.lineThrough, color: p.inkMuted)),
                                Text(m.correction!, style: context.reading.copyWith(fontSize: 16, color: p.success)),
                              ] else
                                Text(m.detail, style: context.reading.copyWith(fontSize: 16)),
                            ]),
                          ),
                        ),
                    ],
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
