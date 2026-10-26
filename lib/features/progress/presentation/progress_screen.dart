import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../../drill/application/drill_words.dart';
import '../../drill/domain/vocab_drill.dart';
import '../../vocabulary/domain/vocab_status.dart';
import '../../practice/domain/practice_generator.dart';
import '../application/progress_providers.dart';
import '../data/stats_repository.dart';

final _statusCountsProvider = FutureProvider<Map<VocabStatus, int>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(vocabRepositoryProvider).statusCounts();
});

final _recurringProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(progressRepositoryProvider).recurringIssues();
});

typedef _SkillStats = ({int right, int total, int words, List<String> weak});

/// Vocabulary drill and listening results from exercise attempts.
final _drillStatsProvider = FutureProvider<_SkillStats>((ref) async {
  ref.watch(dataRevisionProvider);
  final repo = ref.watch(progressRepositoryProvider);
  final stats = await repo.itemStats('drill');
  var right = 0, wrong = 0;
  for (final v in stats.values) {
    right += v.right;
    wrong += v.wrong;
  }
  return (right: right, total: right + wrong, words: {for (final k in stats.keys) lexemeOfDrillItem(k)}.length, weak: await weakLexemeIds(repo));
});

final _listeningStatsProvider = FutureProvider<_SkillStats>((ref) async {
  ref.watch(dataRevisionProvider);
  final stats = await ref.watch(progressRepositoryProvider).itemStats('listening');
  var right = 0, wrong = 0;
  for (final v in stats.values) {
    right += v.right;
    wrong += v.wrong;
  }
  return (right: right, total: right + wrong, words: stats.length, weak: const <String>[]);
});

const _ruleInfo = <String, (String, String)>{
  'perfekt_sein': ('Perfekt\'te sein/haben seçimi', 'g_perfekt'),
  'akkusativ_der': ('Eril isimlerde Akkusativ (einen/den)', 'g_akkusativ'),
  'akkusativ_die': ('Dişil isimlerde artikel', 'g_akkusativ'),
  'akkusativ_das': ('Nötr isimlerde artikel', 'g_akkusativ'),
  'verb_zweit': ('Fiil ikinci sırada', 'g_verbzweit'),
  'noun_caps': ('İsimleri büyük harfle yazmak', 'g_artikel'),
};

/// Progress as evidence of learning, never as time spent.
class ProgressScreen extends ConsumerWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(statsProvider);
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Gelişimin')),
      body: AsyncView<LearningStats>(
        value: stats,
        onRetry: () => ref.invalidate(statsProvider),
        builder: (s) => ListView(padding: pagePadding, children: [PageWidth(child: _Body(s: s))]),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.s});
  final LearningStats s;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final counts = ref.watch(_statusCountsProvider).valueOrNull ?? const {};
    final recurring = ref.watch(_recurringProvider).valueOrNull ?? const {};
    final profile = ref.watch(profileProvider).valueOrNull;
    final drill = ref.watch(_drillStatsProvider).valueOrNull;
    final listening = ref.watch(_listeningStatsProvider).valueOrNull;
    final lexicon = ref.watch(contentProvider).lexicon;
    final totalWords = counts.values.fold<int>(0, (a, b) => a + b);
    final maxWeek = s.weeklyUnaided.fold<int>(1, (a, b) => a > b ? a : b);

    Widget stat(String value, String label, {String? sub}) => Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value, style: context.text.headlineSmall),
              Text(label, style: context.text.bodySmall),
              if (sub != null) Text(sub, style: context.text.labelSmall),
            ]),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Burada ekranda geçirdiğin süreyi değil, gerçekten ne öğrendiğini görmeye çalışıyoruz. Sayılar yaklaşık tahminlerdir.', style: context.text.bodySmall),
      const SectionTitle('Hatırlama'),
      Row(children: [
        stat('${s.unaidedRecallsThisWeek}', 'bu hafta ipucusuz hatırlama', sub: s.assistedRecallsThisWeek > 0 ? '+${s.assistedRecallsThisWeek} ipucuyla' : null),
        const SizedBox(width: 10),
        stat(s.delayedRetention == null ? '—' : '%${(s.delayedRetention! * 100).round()}', 'gecikmeli tekrarda hatırlama',
            sub: s.delayedRetention == null ? '7+ gün sonraki tekrarlar gerekli' : '${s.delayedReviews} gecikmeli tekrar'),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        stat('${s.productionSuccesses}', 'kez Almancasını kendin yazdın'),
        const SizedBox(width: 10),
        stat('${s.contextsTotal}', 'kelime–bağlam bağlantısı'),
      ]),
      const SectionTitle('Son 6 hafta · ipucusuz hatırlama'),
      AppCard(
        child: Semantics(
          label: 'Haftalık ipucusuz hatırlama: ${s.weeklyUnaided.join(', ')}',
          excludeSemantics: true,
          child: SizedBox(
            height: 120,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < s.weeklyUnaided.length; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                      Text('${s.weeklyUnaided[i]}', style: context.text.labelSmall),
                      const SizedBox(height: 4),
                      Container(
                        height: 80 * (s.weeklyUnaided[i] / maxWeek) + 2,
                        decoration: BoxDecoration(color: i == s.weeklyUnaided.length - 1 ? p.primary : p.primary.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(6)),
                      ),
                      const SizedBox(height: 4),
                      Text(i == s.weeklyUnaided.length - 1 ? 'bu' : '-${s.weeklyUnaided.length - 1 - i}', style: context.text.labelSmall),
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      ),
      const SectionTitle('Kelime hazinen'),
      AppCard(
        child: totalWords == 0
            ? Text('Henüz kayıtlı kelime yok.', style: context.text.bodyMedium)
            : Column(children: [
                for (final st in VocabStatus.values)
                  if ((counts[st] ?? 0) > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(children: [
                        SizedBox(width: 130, child: Text(st.labelTr, style: context.text.bodyMedium)),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(value: (counts[st] ?? 0) / totalWords, minHeight: 10),
                          ),
                        ),
                        SizedBox(width: 36, child: Text('${counts[st]}', textAlign: TextAlign.end, style: context.text.labelMedium)),
                      ]),
                    ),
                const SizedBox(height: 6),
                Text('"Kalıcı" durumu için uzun aralıklarla, farklı alıştırma türlerinde ipucusuz hatırlama gerekir.', style: context.text.bodySmall),
              ]),
      ),
      const SectionTitle('Tamamladıkların'),
      Row(children: [
        stat('${s.lessonsCompleted}', 'ders'),
        const SizedBox(width: 10),
        stat('${s.episodesCompleted}', 'hikâye bölümü'),
        const SizedBox(width: 10),
        stat('${s.scenariosCompleted}', 'gerçek durum'),
      ]),
      const SizedBox(height: 10),
      AppCard(
        onTap: () => context.push('/mistakes'),
        child: Row(children: [
          Icon(Icons.edit_note_rounded, color: p.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Hata defteri', style: context.text.titleSmall),
              Text('Yanlış yaptığın her şey tek yerde; haftada bir kısa düzeltme turu.', style: context.text.bodySmall),
            ]),
          ),
          const Icon(Icons.chevron_right_rounded),
        ]),
      ),
      if ((drill?.total ?? 0) > 0 || (listening?.total ?? 0) > 0) ...[
        const SectionTitle('Antrenman ve dinleme'),
        Row(children: [
          if (drill != null && drill.total > 0)
            stat('%${(drill.right * 100 / drill.total).round()}', 'kelime antrenmanı doğru', sub: '${drill.words} kelime · ${drill.total} cevap'),
          if (drill != null && drill.total > 0 && listening != null && listening.total > 0) const SizedBox(width: 10),
          if (listening != null && listening.total > 0)
            stat('%${(listening.right * 100 / listening.total).round()}', 'dinleme sorusu doğru', sub: '${listening.total} cevap'),
        ]),
        if (drill != null && drill.weak.isNotEmpty) ...[
          const SizedBox(height: 10),
          AppCard(
            onTap: () => context.push('/drill/run?src=weak&mode=mixed&n=10'),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Zorlandığın kelimeler', style: context.text.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    [for (final id in drill.weak.take(6)) ?lexicon.byId(id)?.headword].join(' · '),
                    style: context.text.bodySmall,
                  ),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ],
      ],
      if (recurring.isNotEmpty) ...[
        const SectionTitle('Sık tekrarlanan zorluklar'),
        Text('Konuşmalardaki düzeltmelerden çıkarıldı. Tek bir hatadan genelleme yapmıyoruz; yanlış buluyorsan ayarlardan sıfırlayabilirsin.', style: context.text.bodySmall),
        const SizedBox(height: 8),
        for (final e in (recurring.entries.where((e) => e.value >= 2).toList()..sort((a, b) => b.value.compareTo(a.value))).take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              onTap: _ruleInfo[e.key] == null
                  ? null
                  : () {
                      final topic = PracticeTopic.forRule(e.key);
                      context.push(topic != null ? '/practice/${topic.name}' : '/grammar/${_ruleInfo[e.key]!.$2}');
                    },
              child: Row(children: [
                Expanded(child: Text(_ruleInfo[e.key]?.$1 ?? e.key, style: context.text.titleSmall)),
                Text('${e.value} kez', style: context.text.labelSmall),
                const Icon(Icons.chevron_right_rounded),
              ]),
            ),
          ),
      ],
      if (profile != null && !profile.skills.isEmpty) ...[
        const SectionTitle('Başlangıç tahmini (seviye denemesi)'),
        AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Kelime: ${profile.skills.vocabulary ?? '—'} · Dil bilgisi: ${profile.skills.grammar ?? '—'} · Okuma: ${profile.skills.reading ?? '—'}', style: context.text.bodyMedium),
            const SizedBox(height: 4),
            Text('Bu kısa bir deneme sonucuydu, ölçüm değil.', style: context.text.bodySmall),
          ]),
        ),
      ],
    ]);
  }
}
