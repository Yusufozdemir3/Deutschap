import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../application/world_providers.dart';
import '../domain/world_progress.dart';

IconData milestoneIcon(String name) => switch (name) {
      'flag' => Icons.flag_rounded,
      'cafe' => Icons.local_cafe_rounded,
      'phone' => Icons.phone_in_talk_rounded,
      'forum' => Icons.forum_rounded,
      'book' => Icons.menu_book_rounded,
      'search' => Icons.manage_search_rounded,
      'route' => Icons.route_rounded,
      'school' => Icons.school_rounded,
      'mail' => Icons.mail_rounded,
      'memory' => Icons.psychology_rounded,
      'article' => Icons.spellcheck_rounded,
      'edit' => Icons.edit_rounded,
      'library' => Icons.local_library_rounded,
      'star' => Icons.star_rounded,
      'reading' => Icons.chrome_reader_mode_rounded,
      'map' => Icons.map_rounded,
      _ => Icons.emoji_events_rounded,
    };

/// Milestones for demonstrated abilities. Opening this screen marks new
/// ones as seen, so the home screen celebrates each only once.
class MilestonesScreen extends ConsumerStatefulWidget {
  const MilestonesScreen({super.key});
  @override
  ConsumerState<MilestonesScreen> createState() => _MilestonesScreenState();
}

class _MilestonesScreenState extends ConsumerState<MilestonesScreen> {
  Set<String> _new = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final unseen = await ref.read(unseenMilestonesProvider.future);
      if (!mounted || unseen.isEmpty) return;
      setState(() => _new = {for (final m in unseen) m.milestone.id});
      await markMilestonesSeen(ref, _new);
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(milestoneStatusProvider);
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Kilometre taşları')),
      body: AsyncView<List<MilestoneStatus>>(
        value: status,
        onRetry: () => ref.invalidate(milestoneStatusProvider),
        builder: (list) {
          final earned = list.where((m) => m.earned).toList();
          final open = list.where((m) => !m.earned).toList()
            ..sort((a, b) => (b.current / b.target).compareTo(a.current / a.target));
          return ListView(
            padding: pagePadding,
            children: [
              PageWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${earned.length} / ${list.length} kilometre taşı', style: context.text.titleMedium),
                  const SizedBox(height: 4),
                  Text('Her biri gerçek bir beceriye bağlı: bir konuşmayı tamamlamak, kelimeleri haftalar sonra hatırlamak, ilk resmî e-postanı yazmak… Kaybedilmez, sıfırlanmaz.',
                      style: context.text.bodySmall),
                  if (earned.isNotEmpty) ...[
                    const SectionTitle('Kazandıkların'),
                    for (final m in earned) _MilestoneTile(m: m, isNew: _new.contains(m.milestone.id)),
                  ],
                  if (open.isNotEmpty) ...[
                    const SectionTitle('Yoldakiler'),
                    for (final m in open) _MilestoneTile(m: m, isNew: false),
                  ],
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MilestoneTile extends StatelessWidget {
  const _MilestoneTile({required this.m, required this.isNew});
  final MilestoneStatus m;
  final bool isNew;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final ms = m.milestone;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        label: '${ms.titleTr}, ${m.earned ? 'kazanıldı' : '${m.current} / ${m.target}'}',
        child: AppCard(
          color: isNew ? p.accentSoft : null,
          borderColor: isNew ? p.accent : null,
          child: Row(children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(shape: BoxShape.circle, color: m.earned ? p.accent : p.surfaceAlt),
              child: Icon(milestoneIcon(ms.icon), color: m.earned ? p.onPrimary : p.inkMuted),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Text(ms.titleTr, style: context.text.titleSmall)),
                  if (isNew) ...[const SizedBox(width: 8), Pill('Yeni!', color: p.accent, textColor: p.onPrimary)],
                ]),
                const SizedBox(height: 2),
                Text(ms.descriptionTr, style: context.text.bodySmall),
                if (!m.earned) ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: m.target == 0 ? 0 : m.current / m.target, minHeight: 8),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('${m.current}/${m.target}', style: context.text.labelSmall),
                  ]),
                ],
              ]),
            ),
            if (m.earned) Icon(Icons.check_circle_rounded, color: p.success),
          ]),
        ),
      ),
    );
  }
}
