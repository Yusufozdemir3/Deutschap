import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/discover.dart';
import '../../../core/clock.dart';
import '../../../ui/widgets.dart';
import '../../progress/application/progress_providers.dart';
import '../../world/presentation/world_home_section.dart';
import '../application/home_providers.dart';
import '../domain/recommender.dart';

/// One clear priority, a few optional extras, and nothing endless.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final now = ref.watch(clockProvider)();
    final greeting = now.hour >= 5 && now.hour < 11 ? 'Guten Morgen' : (now.hour >= 11 && now.hour < 18 ? 'Guten Tag' : 'Guten Abend');
    final name = profile?.name;
    final cont = ref.watch(continueItemProvider);
    final home = ref.watch(homeDataProvider);
    final p = context.palette;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async => ref.bumpData(),
          child: ListView(
            padding: pagePadding,
            children: [
              PageWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 12),
                  Text('$greeting${name == null ? '' : ', $name'}!', style: context.text.headlineMedium!.copyWith(fontFamily: 'Literata')),
                  Text(_subtitle(now), style: context.text.bodyMedium!.copyWith(color: p.inkMuted)),
                  const NewMilestoneBanner(),
                  if (cont != null) ...[
                    const SectionTitle('Kaldığın yerden devam et'),
                    AppCard(
                      onTap: () => context.push(cont.route),
                      child: Row(children: [
                        Icon(Icons.play_circle_fill_rounded, color: p.primary, size: 36),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(cont.title, style: context.text.titleMedium),
                            Text(cont.subtitle, style: context.text.bodySmall),
                          ]),
                        ),
                      ]),
                    ),
                  ],
                  const SectionTitle('Bugün için önerimiz'),
                  AsyncView<HomeData>(
                    value: home,
                    onRetry: () => ref.invalidate(homeDataProvider),
                    builder: (d) => _Recommendations(recs: d.recommendations),
                  ),
                  const KiezHomeCard(),
                  const _PhraseOfDay(),
                  const _WeekSummary(),
                  const SizedBox(height: 12),
                  Center(
                    child: Text('Bugün istediğin kadar öğren. Bırakmak istediğinde ilerlemen kayıtlı.', style: context.text.bodySmall, textAlign: TextAlign.center),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _subtitle(DateTime now) {
    const days = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];
    const daysDe = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
    return '${days[now.weekday - 1]} · auf Deutsch: ${daysDe[now.weekday - 1]}';
  }
}

class _Recommendations extends StatelessWidget {
  const _Recommendations({required this.recs});
  final List<Recommendation> recs;

  IconData _icon(ActivityKind k) => switch (k) {
        ActivityKind.review => Icons.replay_circle_filled_rounded,
        ActivityKind.lesson => Icons.route_rounded,
        ActivityKind.story => Icons.menu_book_rounded,
        ActivityKind.scenario => Icons.forum_rounded,
        ActivityKind.reading => Icons.article_rounded,
        ActivityKind.discover => Icons.explore_rounded,
        ActivityKind.practice => Icons.fitness_center_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (recs.isEmpty) {
      return AppCard(
        child: Text('Şu an planlı bir şey yok – Keşfet\'te kısa bir oturuma ne dersin?', style: context.text.bodyLarge),
      );
    }
    final main = recs.first;
    final alts = recs.skip(1).where((r) => r.kind != main.kind).take(2).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        color: p.primary,
        borderColor: p.primary,
        padding: const EdgeInsets.all(20),
        onTap: () => context.push(main.route),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(_icon(main.kind), color: p.onPrimary),
            const SizedBox(width: 8),
            Text('${main.minutes} dk', style: context.text.labelMedium!.copyWith(color: p.onPrimary.withValues(alpha: 0.85))),
          ]),
          const SizedBox(height: 10),
          Text(main.titleTr, style: context.text.titleLarge!.copyWith(color: p.onPrimary)),
          const SizedBox(height: 8),
          Text('Neden? ${main.reasonTr}', style: context.text.bodyMedium!.copyWith(color: p.onPrimary.withValues(alpha: 0.9))),
          const SizedBox(height: 14),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: p.onPrimary, foregroundColor: p.primary, minimumSize: const Size(120, 46)),
            onPressed: () => context.push(main.route),
            child: const Text('Başla'),
          ),
        ]),
      ),
      if (alts.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('ya da', style: context.text.labelSmall),
        const SizedBox(height: 6),
        for (final r in alts)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              onTap: () => context.push(r.route),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(children: [
                Icon(_icon(r.kind), color: p.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r.titleTr, style: context.text.titleSmall),
                    Text(r.reasonTr, style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ]),
                ),
                Text('${r.minutes} dk', style: context.text.labelSmall),
              ]),
            ),
          ),
      ],
    ]);
  }
}

class _PhraseOfDay extends ConsumerWidget {
  const _PhraseOfDay();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(contentProvider).discover.where((c) => c.kind == DiscoverKind.phrase).toList();
    if (cards.isEmpty) return const SizedBox.shrink();
    final now = ref.watch(clockProvider)();
    final day = DateTime(now.year, now.month, now.day).difference(DateTime(2026)).inDays;
    final c = cards[day % cards.length];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionTitle('Bugünün ifadesi'),
      AppCard(
        onTap: () => context.go('/entdecken'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(c.title, style: context.text.titleLarge!.copyWith(fontFamily: 'Literata'))),
            SpeakButton(c.bodyDe),
          ]),
          Text(c.bodyDe, style: context.reading.copyWith(fontSize: 17)),
          Text(c.bodyTr, style: context.text.bodySmall),
          const SizedBox(height: 8),
          Text(c.explainTr, style: context.text.bodyMedium, maxLines: 3, overflow: TextOverflow.ellipsis),
        ]),
      ),
    ]);
  }
}

class _WeekSummary extends ConsumerWidget {
  const _WeekSummary();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final days = ref.watch(activeDaysThisWeekProvider).valueOrNull ?? const {};
    final stats = ref.watch(statsProvider).valueOrNull;
    final goal = ref.watch(profileProvider).valueOrNull?.weeklyGoalDays ?? 3;
    final now = ref.watch(clockProvider)();
    final monday = startOfWeek(now);
    const labels = ['Pt', 'Sa', 'Ça', 'Pe', 'Cu', 'Ct', 'Pz'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionTitle('Bu hafta', trailing: TextButton(onPressed: () => context.push('/progress'), child: const Text('Gelişimin'))),
      AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(
            label: 'Bu hafta ${days.length} gün öğrendin, hedefin $goal gün',
            excludeSemantics: true,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              for (var i = 0; i < 7; i++)
                () {
                  final d = monday.add(Duration(days: i));
                  final active = days.contains(DateTime(d.year, d.month, d.day));
                  final today = d.day == now.day && d.month == now.month;
                  return Column(children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: active ? p.success : null,
                        border: Border.all(color: today ? p.primary : p.line, width: today ? 2 : 1),
                      ),
                      child: active ? Icon(Icons.check_rounded, size: 18, color: p.onPrimary) : null,
                    ),
                    const SizedBox(height: 4),
                    Text(labels[i], style: context.text.labelSmall),
                  ]);
                }(),
            ]),
          ),
          const SizedBox(height: 12),
          Text(
            days.length >= goal ? 'Haftalık hedefine ulaştın (${days.length}/$goal gün). Gerisi tamamen bonus.' : 'Haftalık hedef: $goal gün · şu ana kadar ${days.length}. Bir günü kaçırmak hiçbir şeyi sıfırlamaz.',
            style: context.text.bodyMedium,
          ),
          if (stats != null && stats.unaidedRecallsThisWeek > 0) ...[
            const SizedBox(height: 4),
            Text('Bu hafta ${stats.unaidedRecallsThisWeek} kez ipucusuz hatırladın.', style: context.text.bodySmall),
          ],
        ]),
      ),
    ]);
  }
}
