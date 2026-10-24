import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/story.dart';
import '../../../ui/widgets.dart';
import '../../vocabulary/application/vocab_providers.dart';
import '../../vocabulary/domain/vocab_entry.dart';
import '../domain/episode_text.dart';
import '../domain/story_runner.dart';

/// End of an episode: recap, key vocabulary, grammar insights and a short
/// comprehension check. Nothing here blocks the next episode.
class EpisodeRecap extends ConsumerStatefulWidget {
  const EpisodeRecap({super.key, required this.episode, required this.story, required this.history, required this.onReplay});
  final Episode episode;
  final Story story;
  final List<StoryStep> history;
  final VoidCallback onReplay;
  @override
  ConsumerState<EpisodeRecap> createState() => _EpisodeRecapState();
}

class _EpisodeRecapState extends ConsumerState<EpisodeRecap> {
  int _q = 0;
  int? _picked;
  int _correct = 0;
  bool _quizDone = false;
  bool _recorded = false;

  Episode get e => widget.episode;
  String _fill(String s) => fillName(s, ref.read(profileProvider).valueOrNull?.name);

  Future<void> _record() async {
    if (_recorded) return;
    _recorded = true;
    await ref.read(progressRepositoryProvider).completeEpisode(e.id, quizCorrect: _correct, quizTotal: _quizDone ? e.quiz.length : 0);
    ref.bumpData();
  }

  void _answer(int i) {
    if (_picked != null) return;
    setState(() {
      _picked = i;
      if (i == e.quiz[_q].answer) _correct++;
    });
  }

  void _nextQuestion() {
    setState(() {
      _picked = null;
      if (_q + 1 >= e.quiz.length) {
        _quizDone = true;
        _record();
      } else {
        _q++;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final content = ref.watch(contentProvider);
    final saved = ref.watch(savedLexemeIdsProvider).valueOrNull ?? const {};
    final runner = StoryRunner(e);
    final acc = widget.history.isEmpty ? null : runner.choiceAccuracy(widget.history);
    final level = ref.watch(profileProvider).valueOrNull?.level ?? 'A1';
    final nextNumbers = widget.story.episodeNumbers.where((n) => n > e.number);
    final next = nextNumbers.isEmpty ? null : widget.story.variantFor(nextNumbers.first, level);
    final scenario = e.scenarioId == null ? null : content.scenario(e.scenarioId!);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: 'Kapat',
          onPressed: () async {
            await _record();
            if (context.mounted) closeOrHome(context);
          },
        ),
        title: Text('Bölüm özeti', style: context.text.titleMedium),
      ),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(e.title, style: context.text.headlineMedium!.copyWith(fontFamily: 'Literata')),
              const SizedBox(height: 10),
              Text(_fill(e.recapTr), style: context.text.bodyLarge),
              if (acc != null && acc.total > 0) ...[
                const SizedBox(height: 12),
                Pill('Seçimlerin ${acc.firstTry}/${acc.total} tanesinde ilk denemede doğru ifadeyi buldun', icon: Icons.chat_bubble_outline_rounded),
              ],
              const SectionTitle('Önemli kelimeler ve ifadeler'),
              for (final id in e.vocab)
                if (content.lexicon.byId(id) case final l?)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: AppCard(
                      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
                      child: Row(children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Headword(lemma: l.lemma, article: l.article),
                            Text(l.tr, style: context.text.bodySmall),
                          ]),
                        ),
                        SpeakButton(l.headword, size: 20),
                        IconButton(
                          tooltip: saved.contains(id) ? 'Kayıtlı' : 'Kaydet',
                          icon: Icon(saved.contains(id) ? Icons.bookmark_rounded : Icons.bookmark_add_outlined, color: saved.contains(id) ? p.success : p.primary),
                          onPressed: saved.contains(id)
                              ? null
                              : () async {
                                  final occ = findOccurrence(e, id, content.lexicon);
                                  await saveLexeme(
                                    ref,
                                    l,
                                    SourceContext(
                                      type: SourceType.story,
                                      sourceId: e.id,
                                      title: '${widget.story.title} – ${e.title}',
                                      sentence: occ == null ? '' : _fill(occ.de),
                                      sentenceTr: occ == null ? null : _fill(occ.tr),
                                    ),
                                  );
                                },
                        ),
                      ]),
                    ),
                  ),
              if (e.grammar.isNotEmpty) ...[
                const SectionTitle('Dil bilgisi notları'),
                for (final g in e.grammar)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      onTap: g.conceptId == null ? null : () => context.push('/grammar/${g.conceptId}'),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.titleTr, style: context.text.titleSmall),
                        const SizedBox(height: 4),
                        Text(g.bodyTr, style: context.text.bodyMedium),
                        const SizedBox(height: 6),
                        Text(_fill(g.exampleDe), style: context.reading.copyWith(fontSize: 16)),
                        if (g.conceptId != null) Text('Konuyu aç →', style: context.text.labelMedium!.copyWith(color: p.primary)),
                      ]),
                    ),
                  ),
              ],
              if (e.quiz.isNotEmpty) ...[
                const SectionTitle('Anladın mı? (isteğe bağlı)'),
                _quiz(context),
              ],
              const SectionTitle('Sırada'),
              if (scenario != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    onTap: () async {
                      await _record();
                      if (context.mounted) context.pushReplacement('/scenario/${scenario.id}');
                    },
                    child: Row(children: [
                      Icon(Icons.forum_rounded, color: p.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Konuşarak pekiştir: ${scenario.titleTr}', style: context.text.titleSmall),
                          Text('Bölümdeki ifadeleri kendi cümlelerinle kullan.', style: context.text.bodySmall),
                        ]),
                      ),
                    ]),
                  ),
                ),
              if (e.teaserTr != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(16)),
                  child: Text(e.teaserTr!, style: context.text.bodyMedium!.copyWith(fontStyle: FontStyle.italic)),
                ),
              const SizedBox(height: 12),
              if (next != null)
                FilledButton(
                  onPressed: () async {
                    await _record();
                    if (context.mounted) context.pushReplacement('/episode/${next.id}');
                  },
                  child: Text('Sonraki bölüm: ${next.title}'),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () async {
                  await _record();
                  if (context.mounted) closeOrHome(context);
                },
                child: const Text('Şimdilik bu kadar'),
              ),
              TextButton(onPressed: widget.onReplay, child: const Text('Bölümü tekrar oyna')),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _quiz(BuildContext context) {
    final p = context.palette;
    if (_quizDone) {
      return FeedbackPanel(
        positive: _correct == e.quiz.length,
        neutral: _correct != e.quiz.length,
        title: '${e.quiz.length} sorudan $_correct tanesini doğru cevapladın',
        body: _correct == e.quiz.length ? 'Bölümü iyi anlamışsın.' : 'Kaçırdığın yerleri bölümü tekrar oynayarak görebilirsin – zorunlu değil.',
      );
    }
    final q = e.quiz[_q];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${_q + 1}/${e.quiz.length}', style: context.text.labelSmall),
        const SizedBox(height: 4),
        Text(q.questionTr, style: context.text.titleSmall),
        const SizedBox(height: 10),
        for (var i = 0; i < q.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AppCard(
              onTap: _picked == null ? () => _answer(i) : null,
              color: _picked == null ? null : (i == q.answer ? p.successSoft : (i == _picked ? p.dangerSoft : null)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text(q.options[i], style: context.text.bodyMedium),
            ),
          ),
        if (_picked != null) ...[
          const SizedBox(height: 4),
          Text(_fill(q.explainTr), style: context.text.bodySmall),
          const SizedBox(height: 8),
          FilledButton(onPressed: _nextQuestion, child: Text(_q + 1 >= e.quiz.length ? 'Bitir' : 'Sonraki soru')),
        ] else
          TextButton(
            onPressed: () => setState(() {
              _quizDone = true;
              _record();
            }),
            child: const Text('Testi atla'),
          ),
      ]),
    );
  }
}
