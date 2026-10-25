import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../application/world_providers.dart';
import '../domain/world_progress.dart';
import 'kiez_map.dart';
import 'milestones_screen.dart';

/// Celebrates newly earned milestones once, with an explicit dismiss.
class NewMilestoneBanner extends ConsumerWidget {
  const NewMilestoneBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unseen = ref.watch(unseenMilestonesProvider).valueOrNull ?? const [];
    if (unseen.isEmpty) return const SizedBox.shrink();
    final p = context.palette;
    final first = unseen.first.milestone;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AppCard(
        color: p.accentSoft,
        borderColor: p.accent,
        onTap: () => context.push('/milestones'),
        child: Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(shape: BoxShape.circle, color: p.accent),
            child: Icon(milestoneIcon(first.icon), color: p.onPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(unseen.length == 1 ? 'Yeni kilometre taşı!' : '${unseen.length} yeni kilometre taşı!', style: context.text.labelMedium!.copyWith(color: p.accent)),
              Text(first.titleTr, style: context.text.titleSmall),
              Text(first.descriptionTr, style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
          IconButton(
            tooltip: 'Kapat',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => markMilestonesSeen(ref, unseen.map((m) => m.milestone.id)),
          ),
        ]),
      ),
    );
  }
}

/// Compact map plus links to the mystery board and milestones.
class KiezHomeCard extends ConsumerWidget {
  const KiezHomeCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(contentProvider);
    final facts = ref.watch(progressFactsProvider).valueOrNull;
    if (facts == null || content.places.isEmpty) return const SizedBox.shrink();
    final open = {for (final pl in content.places) if (isUnlocked(pl, facts)) pl.id};
    final revealed = content.clues.where((c) => clueState(c, facts) != ClueState.hidden).length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Kiez\'in', trailing: Text('${open.length}/${content.places.length} yer', style: context.text.labelSmall)),
      AppCard(
        padding: const EdgeInsets.all(10),
        onTap: () => context.push('/kiez'),
        semanticLabel: 'Mahalle haritası, ${open.length} / ${content.places.length} yer açık',
        child: KiezMap(places: content.places, unlocked: open, compact: true),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: Tag('Gizem panosu · $revealed/${content.clues.length}', icon: Icons.manage_search_rounded, onTap: () => context.push('/mystery')),
        ),
        const SizedBox(width: 8),
        Expanded(child: Tag('Kilometre taşları', icon: Icons.emoji_events_rounded, onTap: () => context.push('/milestones'))),
      ]),
    ]);
  }
}
