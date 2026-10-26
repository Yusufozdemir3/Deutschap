import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/data/progress_repository.dart';

/// Twenty short lessons on what Turkish speakers typically get wrong.
class TrapsScreen extends ConsumerWidget {
  const TrapsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traps = ref.watch(contentProvider).traps;
    final progress = ref.watch(lessonProgressProvider).valueOrNull ?? const {};
    final p = context.palette;
    final done = traps.where((l) => progress[l.id]?.status == LessonStatus.completed).length;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Türkçe konuşanlara özel')),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Türkçeden aktarılan alışkanlıklar Almancada en sık yapılan hataların kaynağıdır. Her ders 3 dakika: '
                  'önce Türkçe ile karşılaştırma, sonra kısa alıştırmalar. $done/${traps.length} tamamlandı.', style: context.text.bodySmall),
              const SizedBox(height: 10),
              for (final (i, l) in traps.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    onTap: () => context.push('/lesson/${l.id}'),
                    padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                    child: Row(children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: progress[l.id]?.status == LessonStatus.completed ? p.successSoft : p.surfaceAlt,
                        child: progress[l.id]?.status == LessonStatus.completed
                            ? Icon(Icons.check_rounded, color: p.success, size: 18)
                            : Text('${i + 1}', style: context.text.labelMedium),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(l.titleTr, style: context.text.titleSmall),
                          Text(l.objectiveTr, style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                      const Icon(Icons.chevron_right_rounded),
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
