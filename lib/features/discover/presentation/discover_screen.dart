import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/discover.dart';
import '../../../core/clock.dart';
import '../../../ui/german_text.dart';
import '../../../ui/widgets.dart';
import '../../home/domain/recommender.dart';
import '../../profile/domain/learner_profile.dart';
import '../../vocabulary/domain/vocab_entry.dart';
import '../../vocabulary/presentation/word_sheet.dart';
import '../domain/discover_session.dart';

/// "Entdecken": short sessions of self-contained cards with a clear end.
class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});
  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  static const _seenKey = 'discover_seen';
  List<DiscoverCard>? _session;
  int _i = 0;
  final _answers = <String, int>{};
  final _revealed = <String>{};
  bool _logged = false;

  @override
  void initState() {
    super.initState();
    _newSession();
  }

  Future<void> _newSession() async {
    final seen = (await ref.read(kvStoreProvider).getJson(_seenKey)).map((k, v) => MapEntry(k, v as int));
    final profile = ref.read(profileProvider).valueOrNull ?? const LearnerProfile();
    final s = buildDiscoverSession(
      all: ref.read(contentProvider).discover,
      lastSeen: seen,
      interests: profile.interests,
      hiddenTopics: profile.hiddenTopics,
    );
    if (!mounted) return;
    setState(() {
      _session = s;
      _i = 0;
      _answers.clear();
      _revealed.clear();
      _logged = false;
    });
    if (s.isNotEmpty) unawaited(_markSeen(s.first));
  }

  Future<void> _markSeen(DiscoverCard c) async {
    final kv = ref.read(kvStoreProvider);
    final seen = await kv.getJson(_seenKey);
    seen[c.id] = toMillis(ref.read(clockProvider)());
    await kv.setJson(_seenKey, seen);
  }

  void _next() {
    final s = _session!;
    setState(() => _i++);
    if (_i < s.length) {
      _markSeen(s[_i]);
    } else if (!_logged) {
      _logged = true;
      ref.read(progressRepositoryProvider).logActivity(ActivityKind.discover, summary: '${s.length}').then((_) => ref.bumpData());
    }
  }

  Future<void> _hideTopic(DiscoverCard c) async {
    if (c.topics.isEmpty) return;
    final topic = c.topics.first;
    await ref.read(profileProvider.notifier).edit((p) => p.copyWith(hiddenTopics: {...p.hiddenTopics, topic}));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('"${interestTopics[topic] ?? topic}" konusu artık gösterilmeyecek.'),
        action: SnackBarAction(
          label: 'Geri al',
          onPressed: () => ref.read(profileProvider.notifier).edit((p) => p.copyWith(hiddenTopics: {...p.hiddenTopics}..remove(topic))),
        ),
      ));
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Keşfet'),
        actions: [
          if (s != null && _i < s.length)
            Padding(padding: const EdgeInsets.only(right: 16), child: Center(child: Text('${_i + 1} / ${s.length}', style: context.text.labelMedium))),
        ],
      ),
      body: s == null
          ? const LoadingView()
          : s.isEmpty
              ? EmptyState(
                  icon: Icons.explore_off_outlined,
                  title: 'Gösterecek kart kalmadı',
                  message: 'Gizlediğin konular yüzünden olabilir. Ayarlardan konu tercihlerini değiştirebilirsin.',
                  action: OutlinedButton(onPressed: () => context.push('/settings'), child: const Text('Ayarlar')),
                )
              : _i >= s.length
                  ? _done(context, s)
                  : _card(context, s[_i]),
    );
  }

  Widget _card(BuildContext context, DiscoverCard c) {
    final p = context.palette;
    final lexicon = ref.watch(contentProvider).lexicon;
    final saved = ref.watch(savedLexemeIdsProvider).valueOrNull ?? const {};
    final answered = _answers[c.id];
    final revealed = _revealed.contains(c.id) || answered != null;
    final source = SourceContext(type: SourceType.discover, sourceId: c.id, title: c.title);
    final unsaved = c.lexemes.where((id) => !saved.contains(id) && lexicon.contains(id)).toList();
    return Column(children: [
      LinearProgressIndicator(value: (_i + 1) / _session!.length, minHeight: 3),
      Expanded(
        child: ListView(
          padding: pagePadding,
          children: [
            PageWidth(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const SizedBox(height: 8),
                Text(c.kind.labelTr.toUpperCase(), style: context.text.labelSmall!.copyWith(color: p.accent)),
                const SizedBox(height: 4),
                MetaLine(level: c.level, minutes: c.minutes, objective: c.objectiveTr),
                const SizedBox(height: 16),
                Text(c.title, style: context.text.headlineMedium!.copyWith(fontFamily: 'Literata')),
                const SizedBox(height: 16),
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: TappableGermanText(c.bodyDe, onWordTap: (t) => showWordSheet(context, tap: t, source: source))),
                      SpeakButton(c.bodyDe),
                    ]),
                    if (!c.hasQuestion || revealed) ...[
                      const SizedBox(height: 6),
                      Text(c.bodyTr, style: context.text.bodyMedium!.copyWith(color: p.inkMuted)),
                    ],
                  ]),
                ),
                const SizedBox(height: 16),
                if (c.hasQuestion) ...[
                  Text(c.question!, style: context.text.titleSmall),
                  const SizedBox(height: 8),
                  for (var k = 0; k < c.options.length; k++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: AppCard(
                        onTap: answered == null ? () => setState(() => _answers[c.id] = k) : null,
                        color: answered == null ? null : (k == c.answer ? p.successSoft : (k == answered ? p.dangerSoft : null)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Text(c.options[k], style: context.reading.copyWith(fontSize: 16)),
                      ),
                    ),
                ] else if (!revealed)
                  OutlinedButton(onPressed: () => setState(() => _revealed.add(c.id)), child: const Text('Açıklamayı göster')),
                if (revealed) ...[
                  const SizedBox(height: 8),
                  FeedbackPanel(
                    positive: answered == null || answered == c.answer,
                    neutral: answered == null,
                    title: answered == null ? 'Neden böyle?' : (answered == c.answer ? 'Doğru tahmin!' : 'İyi deneme'),
                    body: c.explainTr,
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (unsaved.isNotEmpty)
                    Tag(
                      'Kelimeleri kaydet (${unsaved.length})',
                      icon: Icons.bookmark_add_outlined,
                      onTap: () async {
                        for (final id in unsaved) {
                          await ref.read(vocabRepositoryProvider).saveLexeme(lexicon.byId(id)!,
                              context: SourceContext(type: SourceType.discover, sourceId: c.id, title: c.title, sentence: c.bodyDe, sentenceTr: c.bodyTr));
                        }
                        ref.bumpData();
                        if (context.mounted) showToast(context, 'Kaydedildi');
                      },
                    ),
                  if (c.topics.isNotEmpty) Tag('Bu konuyu gösterme', icon: Icons.visibility_off_outlined, onTap: () => _hideTopic(c)),
                ]),
              ]),
            ),
          ],
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: PageWidth(child: SizedBox(width: double.infinity, child: FilledButton(onPressed: _next, child: Text(_i + 1 == _session!.length ? 'Oturumu bitir' : 'Sonraki')))),
        ),
      ),
    ]);
  }

  Widget _done(BuildContext context, List<DiscoverCard> s) {
    final p = context.palette;
    final correct = s.where((c) => c.hasQuestion && _answers[c.id] == c.answer).length;
    final asked = s.where((c) => c.hasQuestion && _answers.containsKey(c.id)).length;
    return ListView(
      padding: pagePadding,
      children: [
        PageWidth(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 24),
            Icon(Icons.wb_twilight_rounded, size: 52, color: p.accent),
            const SizedBox(height: 8),
            Text('Oturum tamamlandı', style: context.text.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text('${s.length} kısa kart${asked > 0 ? ' · $asked tahminin $correct tanesi doğru' : ''}', style: context.text.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            AppCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Bugün öğrendiklerin', style: context.text.titleSmall),
                const SizedBox(height: 6),
                for (final c in s) Text('• ${c.objectiveTr}', style: context.text.bodyMedium),
              ]),
            ),
            const SizedBox(height: 16),
            Text('Burada durmak iyi bir fikir. Öğrendiklerin, kaydettiğin kelimelerle birlikte seni bekliyor.', style: context.text.bodySmall, textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton(onPressed: () => context.go('/heute'), child: const Text('Ana sayfaya dön')),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: _newSession, child: const Text('Bir oturum daha')),
          ]),
        ),
      ],
    );
  }
}
