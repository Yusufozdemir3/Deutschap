import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/lesson.dart';
import '../../../ui/widgets.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/data/progress_repository.dart';
import '../../reading/data/reading_repository.dart';

enum LearnTab {
  path('Yol'),
  stories('Hikâyeler'),
  talk('Konuşma'),
  read('Okuma');

  const LearnTab(this.label);
  final String label;

  static LearnTab fromQuery(String? q) => LearnTab.values.firstWhere((t) => t.name == q, orElse: () => LearnTab.path);
}

class LearnScreen extends StatelessWidget {
  const LearnScreen({super.key, this.initialTab = LearnTab.path});
  final LearnTab initialTab;

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: LearnTab.values.length,
        initialIndex: initialTab.index,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Öğren'),
            bottom: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [for (final t in LearnTab.values) Tab(text: t.label)],
            ),
          ),
          body: const TabBarView(children: [_PathTab(), _StoriesTab(), _TalkTab(), _ReadTab()]),
        ),
      );
}

class _PathTab extends ConsumerWidget {
  const _PathTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(contentProvider);
    final progress = ref.watch(lessonProgressProvider).valueOrNull ?? const {};
    final next = ref.watch(nextLessonProvider);
    return ListView(
      padding: pagePadding,
      children: [
        PageWidth(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
              child: Text('A1 öğrenme yolu', style: context.text.headlineSmall),
            ),
            Text('Dersler sırayla ilerler ama hepsi açık: istediğin yerden başlayabilirsin.', style: context.text.bodySmall),
            const SizedBox(height: 8),
            for (final u in content.path.units) _UnitCard(unit: u, progress: progress, nextId: next?.id),
          ]),
        ),
      ],
    );
  }
}

class _UnitCard extends ConsumerWidget {
  const _UnitCard({required this.unit, required this.progress, required this.nextId});
  final Unit unit;
  final Map<String, LessonProgress> progress;
  final String? nextId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final grammar = ref.watch(contentProvider).grammar;
    final done = unit.lessons.where((l) => progress[l.id]?.status == LessonStatus.completed).length;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: AppCard(
        color: unit.isPlanned ? p.paper : null,
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Ünite ${unit.number}', style: context.text.labelSmall)),
              if (unit.isPlanned) const Pill('Hazırlanıyor') else if (unit.lessons.isNotEmpty) Text('$done/${unit.lessons.length}', style: context.text.labelSmall),
            ]),
            const SizedBox(height: 4),
            Text(unit.titleDe, style: context.text.titleLarge!.copyWith(fontFamily: 'Literata', color: unit.isPlanned ? p.inkMuted : null)),
            Text(unit.titleTr, style: context.text.bodyMedium!.copyWith(color: p.inkMuted)),
            const SizedBox(height: 6),
            Text(unit.goalTr, style: context.text.bodySmall),
            if (unit.grammar.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final g in unit.grammar)
                  if (grammar[g] != null)
                    Tag(grammar[g]!.titleTr, icon: Icons.lightbulb_outline_rounded, onTap: () => context.push('/grammar/$g')),
              ]),
            ],
            if (unit.lessons.isNotEmpty) const SizedBox(height: 6),
            for (final l in unit.lessons) _LessonRow(lesson: l, progress: progress[l.id], isNext: l.id == nextId),
          ],
        ),
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  const _LessonRow({required this.lesson, required this.progress, required this.isNext});
  final Lesson lesson;
  final LessonProgress? progress;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final status = progress?.status ?? LessonStatus.notStarted;
    final (icon, color, label) = switch (status) {
      LessonStatus.completed => (Icons.check_circle_rounded, p.success, 'tamamlandı'),
      LessonStatus.inProgress => (Icons.timelapse_rounded, p.accent, 'devam ediyor'),
      LessonStatus.notStarted => (Icons.circle_outlined, p.inkMuted, 'başlanmadı'),
    };
    return Semantics(
      button: true,
      label: '${lesson.titleTr}, $label',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/lesson/${lesson.id}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(lesson.titleTr, style: context.text.titleSmall),
                Text('${lesson.minutes} dk · ${lesson.objectiveTr}', style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
              ]),
            ),
            if (isNext) Pill('Sıradaki', color: p.accentSoft, textColor: p.accent),
            Icon(Icons.chevron_right_rounded, color: p.inkMuted),
          ]),
        ),
      ),
    );
  }
}

class _StoriesTab extends ConsumerWidget {
  const _StoriesTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(contentProvider);
    final level = ref.watch(profileProvider).valueOrNull?.level ?? 'A1';
    final progress = ref.watch(episodeProgressProvider).valueOrNull ?? const {};
    final p = context.palette;
    return ListView(
      padding: pagePadding,
      children: [
        for (final s in content.stories)
          PageWidth(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                    color: p.primary,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('HİKÂYE SERİSİ · ${s.episodeNumbers.length} BÖLÜM', style: context.text.labelSmall!.copyWith(color: p.onPrimary.withValues(alpha: 0.8))),
                      const SizedBox(height: 6),
                      Text(s.title, style: context.text.headlineMedium!.copyWith(color: p.onPrimary, fontFamily: 'Literata')),
                      const SizedBox(height: 4),
                      Text(s.subtitleTr, style: context.text.bodyMedium!.copyWith(color: p.onPrimary.withValues(alpha: 0.9))),
                    ]),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                    child: Text(s.premiseTr, style: context.text.bodyMedium),
                  ),
                  for (final n in s.episodeNumbers)
                    () {
                      final e = s.variantFor(n, level);
                      final st = progress[e.id]?.status;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                        leading: CircleAvatar(
                          backgroundColor: st == EpisodeStatus.completed ? p.successSoft : p.surfaceAlt,
                          child: st == EpisodeStatus.completed
                              ? Icon(Icons.check_rounded, color: p.success)
                              : Text('$n', style: context.text.titleSmall),
                        ),
                        title: Text(e.title, style: context.text.titleSmall!.copyWith(fontFamily: 'Literata')),
                        subtitle: Text('${e.level} · ${e.minutes} dk · ${e.learningObjectiveTr}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        trailing: st == EpisodeStatus.inProgress
                            ? Pill('Devam et', color: p.accentSoft, textColor: p.accent)
                            : (s.episodes.where((x) => x.number == n).length > 1 ? Pill(s.episodes.where((x) => x.number == n).map((x) => x.level).join(' · ')) : null),
                        onTap: () => context.push('/episode/${e.id}'),
                      );
                    }(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(onPressed: () => context.push('/story/${s.id}'), child: const Text('Karakterler ve seri hakkında')),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 16),
        PageWidth(child: Text('Yeni bölümler ve seriler hazırlanıyor. Her bölüm A1 dil desteğiyle yazıldı; ileride aynı hikâyelerin A2–B1 sürümleri gelecek.', style: context.text.bodySmall)),
      ],
    );
  }
}

class _TalkTab extends ConsumerWidget {
  const _TalkTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(contentProvider);
    final done = ref.watch(completedScenariosProvider).valueOrNull ?? const {};
    final p = context.palette;
    return ListView(
      padding: pagePadding,
      children: [
        PageWidth(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 8),
            Text('Gerçek hayat simülatörü', style: context.text.headlineSmall),
            const SizedBox(height: 4),
            Text('Bir durumu gerçek hayatta yaşamadan önce prova et. Hatalar sorun değil: önce anlaşılmak, sonra düzeltme.', style: context.text.bodySmall),
            const SizedBox(height: 12),
            for (final s in content.scenarios)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => context.push('/scenario/${s.id}'),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(14)),
                      child: Icon(Icons.forum_rounded, color: p.accent),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(s.titleTr, style: context.text.titleSmall),
                        Text(s.titleDe, style: context.text.bodySmall!.copyWith(fontFamily: 'Literata')),
                        const SizedBox(height: 4),
                        MetaLine(level: s.level, objective: s.objectiveTr),
                      ]),
                    ),
                    if (done.contains(s.id)) Icon(Icons.check_circle_rounded, color: p.success, semanticLabel: 'tamamlandı'),
                  ]),
                ),
              ),
            const SizedBox(height: 8),
            Text('Not: Bu sürümde konuşma ortağı kural tabanlıdır ve çevrimdışı çalışır. Senaryonun hedeflerine uygun cevapları tanır; her cümleyi anlamayabilir.', style: context.text.bodySmall),
          ]),
        ),
      ],
    );
  }
}

class _ReadTab extends ConsumerWidget {
  const _ReadTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(contentProvider);
    final pasted = ref.watch(pastedDocsProvider);
    final positions = ref.watch(builtinPositionsProvider).valueOrNull ?? const {};
    return ListView(
      padding: pagePadding,
      children: [
        PageWidth(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 8),
            Text('Okuma', style: context.text.headlineSmall),
            const SizedBox(height: 4),
            Text('Her kelimeye dokun: anlamını gör, cümlesiyle birlikte kaydet. Kaldığın yer saklanır.', style: context.text.bodySmall),
            const SizedBox(height: 12),
            for (final r in content.readings)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  onTap: () => context.push('/reader/builtin:${r.id}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.title, style: context.text.titleMedium!.copyWith(fontFamily: 'Literata')),
                    const SizedBox(height: 4),
                    MetaLine(level: r.level, minutes: r.minutes, objective: r.topicTr),
                    if ((positions[r.id] ?? 0) > 0) ...[
                      const SizedBox(height: 6),
                      Text('Kaldığın yer: ${positions[r.id]! + 1}. paragraf', style: context.text.labelSmall),
                    ],
                  ]),
                ),
              ),
            SectionTitle('Kendi metinlerin', trailing: TextButton.icon(onPressed: () => context.push('/paste'), icon: const Icon(Icons.add_rounded), label: const Text('Metin ekle'))),
            AsyncView<List<ReadingDoc>>(
              value: pasted,
              onRetry: () => ref.invalidate(pastedDocsProvider),
              builder: (docs) => docs.isEmpty
                  ? EmptyState(
                      icon: Icons.content_paste_rounded,
                      title: 'Henüz kendi metnin yok',
                      message: 'Bir şarkı sözü, haber ya da e-posta… Almanca bir metni yapıştır ve onunla öğren. Metin sadece bu cihazda saklanır.',
                      action: FilledButton.icon(onPressed: () => context.push('/paste'), icon: const Icon(Icons.content_paste_go_rounded), label: const Text('Metin yapıştır')),
                    )
                  : Column(children: [
                      for (final d in docs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: AppCard(
                            onTap: () => context.push('/reader/${d.id}'),
                            child: Row(children: [
                              const Icon(Icons.description_outlined),
                              const SizedBox(width: 12),
                              Expanded(child: Text(d.title, style: context.text.titleSmall)),
                              Text('${d.body.length} karakter', style: context.text.labelSmall),
                            ]),
                          ),
                        ),
                    ]),
            ),
          ]),
        ),
      ],
    );
  }
}
