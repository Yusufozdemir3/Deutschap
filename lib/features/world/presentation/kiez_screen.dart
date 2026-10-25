import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/content_bundle.dart';
import '../../../content/models/world.dart';
import '../../../ui/widgets.dart';
import '../application/world_providers.dart';
import '../domain/world_progress.dart';
import 'kiez_map.dart';

/// The neighbourhood map: places light up as the learner does things
/// there. Locked places say exactly how to open them.
class KiezScreen extends ConsumerWidget {
  const KiezScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(contentProvider);
    final facts = ref.watch(progressFactsProvider);
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Kiez\'in')),
      body: AsyncView<ProgressFacts>(
        value: facts,
        onRetry: () => ref.invalidate(progressFactsProvider),
        builder: (f) {
          final open = {for (final p in content.places) if (isUnlocked(p, f)) p.id};
          return ListView(
            padding: pagePadding,
            children: [
              PageWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${open.length} / ${content.places.length} yer açıldı', style: context.text.titleMedium),
                  const SizedBox(height: 4),
                  Text('Bir yer, orada bir şey yaptığında açılır: bir ders, bir hikâye bölümü ya da bir konuşma. Bir yere dokun, ne gerektiğini gör.',
                      style: context.text.bodySmall),
                  const SizedBox(height: 14),
                  KiezMap(places: content.places, unlocked: open, onTap: (p) => _showPlace(context, content, p, open.contains(p.id))),
                  const SectionTitle('Yerler'),
                  for (final p in content.places)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(open.contains(p.id) ? placeIcon(p.icon) : Icons.lock_outline_rounded,
                          color: open.contains(p.id) ? context.palette.primary : context.palette.inkMuted),
                      title: Text(p.nameDe, style: const TextStyle(fontFamily: 'Literata')),
                      subtitle: Text(open.contains(p.id) ? p.nameTr : '${p.nameTr} · kilitli'),
                      onTap: () => _showPlace(context, content, p, open.contains(p.id)),
                    ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

String describeUnlock(ContentBundle content, UnlockRef r) => switch (r.kind) {
      'lesson' => 'Ders: ${content.lesson(r.id)?.titleTr ?? r.id}',
      'episode' => () {
          final n = int.tryParse(r.id) ?? 0;
          final story = content.stories.firstOrNull;
          final e = story?.episodes.where((e) => e.number == n).firstOrNull;
          return 'Hikâye, $n. bölüm: ${e?.title ?? ''}';
        }(),
      'scenario' => 'Konuşma: ${content.scenario(r.id)?.titleTr ?? r.id}',
      'reading' => 'Okuma: ${content.reading(r.id)?.title ?? r.id}',
      _ => r.toString(),
    };

String routeForUnlock(ContentBundle content, UnlockRef r) => switch (r.kind) {
      'lesson' => '/lesson/${r.id}',
      'episode' => () {
          final n = int.tryParse(r.id) ?? 0;
          final e = content.stories.firstOrNull?.episodes.where((e) => e.number == n).firstOrNull;
          return e == null ? '/lernen?tab=stories' : '/episode/${e.id}';
        }(),
      'scenario' => '/scenario/${r.id}',
      'reading' => '/reader/builtin:${r.id}',
      _ => '/heute',
    };

void _showPlace(BuildContext context, ContentBundle content, Place p, bool open) {
  showModalBottomSheet<void>(
    context: context,
    builder: (sheet) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(open ? placeIcon(p.icon) : Icons.lock_outline_rounded, color: open ? sheet.palette.primary : sheet.palette.inkMuted),
          const SizedBox(width: 10),
          Expanded(child: Text(p.nameDe, style: sheet.text.titleLarge!.copyWith(fontFamily: 'Literata'))),
        ]),
        Text(p.nameTr, style: sheet.text.bodySmall),
        const SizedBox(height: 12),
        if (open) ...[
          Text(p.aboutTr, style: sheet.text.bodyLarge),
          if (p.route != null) ...[
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                Navigator.pop(sheet);
                context.push(p.route!);
              },
              child: const Text('Buraya git'),
            ),
          ],
        ] else ...[
          Text('Bu yeri açmak için şunlardan birini tamamla:', style: sheet.text.bodyMedium),
          const SizedBox(height: 8),
          for (final u in p.unlock)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Tag(describeUnlock(content, u), icon: Icons.arrow_forward_rounded, onTap: () {
                Navigator.pop(sheet);
                context.push(routeForUnlock(content, u));
              }),
            ),
        ],
      ]),
    ),
  );
}
