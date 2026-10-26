import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/data/progress_repository.dart';

/// Series overview: premise, recurring characters and episodes.
class StoryScreen extends ConsumerWidget {
  const StoryScreen({super.key, required this.storyId});
  final String storyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(contentProvider).story(storyId);
    if (s == null) return Scaffold(appBar: AppBar(leading: const BackOrHomeButton()), body: const ErrorState(message: 'Bu hikâye bulunamadı.'));
    final level = ref.watch(profileProvider).valueOrNull?.level ?? 'A1';
    final progress = ref.watch(episodeProgressProvider).valueOrNull ?? const {};
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton()),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(s.title, style: context.text.displaySmall!.copyWith(fontFamily: context.serif)),
              const SizedBox(height: 6),
              Text(s.subtitleTr, style: context.text.titleMedium!.copyWith(color: p.inkMuted).regular),
              const SizedBox(height: 14),
              Text(s.premiseTr, style: context.text.bodyLarge),
              const SectionTitle('Karakterler'),
              for (final c in s.characters)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: CircleAvatar(backgroundColor: p.accentSoft, child: Text(c.name.characters.first, style: TextStyle(color: p.accent))),
                  title: Text(c.name),
                  subtitle: Text(c.roleTr),
                  trailing: c.formal ? const Pill('Sie') : const Pill('du'),
                ),
              const SectionTitle('Bölümler'),
              for (final n in s.episodeNumbers)
                () {
                  final e = s.variantFor(n, level);
                  final done = progress[e.id]?.status == EpisodeStatus.completed;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: () => context.push('/episode/${e.id}'),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('$n. ${e.title}', style: context.text.titleSmall!.copyWith(fontFamily: context.serif)),
                            Text(e.narrativeObjectiveTr, style: context.text.bodySmall),
                          ]),
                        ),
                        if (done) Icon(Icons.check_circle_rounded, color: p.success, semanticLabel: 'tamamlandı'),
                      ]),
                    ),
                  );
                }(),
            ]),
          ),
        ],
      ),
    );
  }
}
