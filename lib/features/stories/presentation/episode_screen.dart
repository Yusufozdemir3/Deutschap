import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/story.dart';
import '../../../ui/german_text.dart';
import '../../../ui/widgets.dart';
import '../../progress/data/progress_repository.dart';
import '../../vocabulary/application/vocab_providers.dart';
import '../../vocabulary/domain/vocab_entry.dart';
import '../../vocabulary/presentation/word_sheet.dart';
import '../domain/episode_text.dart';
import '../domain/story_runner.dart';
import 'episode_recap.dart';

enum _Phase { intro, playing, recap }

class EpisodeScreen extends ConsumerStatefulWidget {
  const EpisodeScreen({super.key, required this.episodeId});
  final String episodeId;
  @override
  ConsumerState<EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends ConsumerState<EpisodeScreen> {
  Episode? _episode;
  Story? _story;
  StoryRunner? _runner;
  StoryState? _state;
  EpisodeProgress? _saved;
  _Phase _phase = _Phase.intro;
  bool _loading = true;
  bool _showTr = false;
  StoryChoice? _feedback;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final content = ref.read(contentProvider);
    final e = content.episode(widget.episodeId);
    if (e == null) {
      setState(() => _loading = false);
      return;
    }
    final saved = await ref.read(progressRepositoryProvider).episode(e.id);
    if (!mounted) return;
    setState(() {
      _episode = e;
      _story = content.storyOfEpisode(e.id);
      _runner = StoryRunner(e);
      _saved = saved;
      _loading = false;
    });
  }

  bool get _canResume {
    final s = _saved;
    return s != null && s.nodeId.isNotEmpty && _episode!.nodes.containsKey(s.nodeId) && _episode!.nodes[s.nodeId] is! EndNode;
  }

  void _start({required bool resume}) {
    final r = _runner!;
    setState(() {
      _state = resume ? StoryState(nodeId: _saved!.nodeId, flags: _saved!.flags, history: _saved!.history) : r.start();
      _feedback = null;
      _phase = _Phase.playing;
    });
    _persist();
  }

  Future<void> _persist() async {
    await ref.read(progressRepositoryProvider).saveEpisodeState(_episode!.id, _story!.id, _state!);
    ref.bumpData();
  }

  void _advance() {
    final r = _runner!;
    setState(() {
      _state = r.advance(_state!);
      _feedback = null;
    });
    _persist();
    _afterMove();
  }

  void _choose(StoryChoice c) {
    final result = _runner!.choose(_state!, c.id);
    setState(() {
      _feedback = c;
      // Accepted choices wait for "Devam" so the learner reads the feedback.
      if (!result.advanced) _state = result.state;
    });
    _pendingAccepted = result.advanced ? result.state : null;
  }

  StoryState? _pendingAccepted;

  void _continueAfterChoice() {
    if (_pendingAccepted == null) {
      setState(() => _feedback = null);
      return;
    }
    setState(() {
      _state = _pendingAccepted;
      _pendingAccepted = null;
      _feedback = null;
    });
    _persist();
    _afterMove();
  }

  void _afterMove() {
    if (_runner!.isAtEnd(_state!)) {
      setState(() => _phase = _Phase.recap);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final reduce = MediaQuery.of(context).disableAnimations;
      if (reduce) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      } else {
        _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
      }
    });
  }

  String _fill(String s) => fillName(s, ref.read(profileProvider).valueOrNull?.name);

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    final e = _episode;
    if (e == null) return Scaffold(appBar: AppBar(leading: const BackOrHomeButton()), body: const ErrorState(message: 'Bu bölüm bulunamadı.'));
    return switch (_phase) {
      _Phase.intro => _intro(context, e),
      _Phase.playing => _player(context, e),
      _Phase.recap => EpisodeRecap(
          episode: e,
          story: _story!,
          history: _state?.history ?? const [],
          onReplay: () => _start(resume: false),
        ),
    };
  }

  Widget _intro(BuildContext context, Episode e) {
    final p = context.palette;
    final completed = _saved?.status == EpisodeStatus.completed;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton()),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('${_story!.title} · Bölüm ${e.number}', style: context.text.labelSmall),
              const SizedBox(height: 6),
              Text(e.title, style: context.text.displaySmall!.copyWith(fontFamily: 'Literata')),
              Text(e.titleTr, style: context.text.titleMedium!.copyWith(color: p.inkMuted)),
              const SizedBox(height: 16),
              MetaLine(level: e.level, minutes: e.minutes),
              const SizedBox(height: 20),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [Icon(Icons.flag_outlined, color: p.accent, size: 20), const SizedBox(width: 8), Text('Hikâyede', style: context.text.titleSmall)]),
                  const SizedBox(height: 4),
                  Text(e.narrativeObjectiveTr, style: context.text.bodyMedium),
                  const SizedBox(height: 14),
                  Row(children: [Icon(Icons.school_outlined, color: p.primary, size: 20), const SizedBox(width: 8), Text('Öğreneceğin', style: context.text.titleSmall)]),
                  const SizedBox(height: 4),
                  Text(e.learningObjectiveTr, style: context.text.bodyMedium),
                ]),
              ),
              const SizedBox(height: 16),
              Text('İpucu: Her kelimeye dokunabilirsin. Cevap seçerken yanlış yapmak sorun değil; açıklamayı okuyup tekrar deneyebilirsin.', style: context.text.bodySmall),
              const SizedBox(height: 24),
              if (_canResume) ...[
                FilledButton(onPressed: () => _start(resume: true), child: const Text('Kaldığın yerden devam et')),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => _start(resume: false), child: const Text('Baştan başla')),
              ] else
                FilledButton(onPressed: () => _start(resume: false), child: Text(completed ? 'Tekrar oyna' : 'Başla')),
              if (completed) ...[
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => setState(() => _phase = _Phase.recap), child: const Text('Bölüm özetini gör')),
              ],
            ]),
          ),
        ],
      ),
    );
  }

  Widget _player(BuildContext context, Episode e) {
    final r = _runner!;
    final s = _state!;
    final known = ref.watch(knownSurfacesProvider);
    final current = r.node(s.nodeId);
    final source = SourceContext(type: SourceType.story, sourceId: e.id, title: '${_story!.title} – ${e.title}');
    final items = <Widget>[];
    for (final h in s.history) {
      items.add(_rendered(context, r.node(h.nodeId), h, source, known));
    }
    if (current is! ChoiceNode) items.add(_rendered(context, current, null, source, known));

    return Scaffold(
      appBar: AppBar(
        title: Text(e.title, style: context.text.titleMedium!.copyWith(fontFamily: 'Literata')),
        actions: [
          IconButton(
            tooltip: _showTr ? 'Çeviriyi gizle' : 'Çeviriyi göster',
            icon: Icon(_showTr ? Icons.translate_rounded : Icons.g_translate_outlined),
            isSelected: _showTr,
            onPressed: () => setState(() => _showTr = !_showTr),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [PageWidth(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: items))],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: PageWidth(child: current is ChoiceNode ? _choicePanel(context, current) : _continueButton(current)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _continueButton(StoryNode current) => SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: current is EndNode ? null : _advance, child: const Text('Devam')),
      );

  Widget _choicePanel(BuildContext context, ChoiceNode node) {
    final p = context.palette;
    final fb = _feedback;
    if (fb != null) {
      final (title, positive, neutral) = switch (fb.verdict) {
        ChoiceVerdict.best => ('Çok iyi!', true, false),
        ChoiceVerdict.ok => ('Anlaşıldı – ama bir not', true, true),
        ChoiceVerdict.wrong => ('Bir daha dene', false, false),
      };
      return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        FeedbackPanel(
          positive: positive,
          neutral: neutral,
          title: title,
          body: _fill(fb.feedbackTr),
          extra: Text(_fill(fb.de), style: context.reading.copyWith(fontSize: 16)),
        ),
        const SizedBox(height: 10),
        FilledButton(onPressed: _continueAfterChoice, child: Text(fb.verdict == ChoiceVerdict.wrong ? 'Tekrar seç' : 'Devam')),
      ]);
    }
    final tried = _state!.pendingWrong;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(node.promptTr, style: context.text.titleSmall),
      const SizedBox(height: 8),
      for (final c in node.choices)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Opacity(
            opacity: tried.contains(c.id) ? 0.5 : 1,
            child: AppCard(
              onTap: tried.contains(c.id) ? null : () => _choose(c),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              semanticLabel: tried.contains(c.id) ? '${_fill(c.de)}, denendi' : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_fill(c.de), style: context.reading.copyWith(fontSize: 17)),
                if (_showTr) Text(_fill(c.tr), style: context.text.bodySmall),
              ]),
            ),
          ),
        ),
      if (tried.isNotEmpty) Text('Yanlış denemeler sorun değil – açıklamalar öğrenmenin parçası.', style: context.text.bodySmall!.copyWith(color: p.inkMuted)),
    ]);
  }

  Widget _rendered(BuildContext context, StoryNode n, StoryStep? h, SourceContext source, Set<String> known) {
    final p = context.palette;
    bool isKnown(String w) => known.contains(w.toLowerCase());
    void tap(WordTap t, String tr) => showWordSheet(context, tap: t, source: source, sentenceTr: _fill(tr));
    switch (n) {
      case NarrationNode(:final de, :final tr):
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TappableGermanText(_fill(de), isKnown: isKnown, style: context.reading.copyWith(fontStyle: FontStyle.italic, color: p.ink), onWordTap: (t) => tap(t, tr)),
            if (_showTr) Text(_fill(tr), style: context.text.bodySmall),
          ]),
        );
      case LineNode(:final speaker, :final de, :final tr, :final glossTr):
        final ch = _story!.character(speaker);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
            decoration: BoxDecoration(color: p.surface, border: Border.all(color: p.line), borderRadius: BorderRadius.circular(16)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(ch?.name ?? speaker, style: context.text.labelMedium!.copyWith(color: p.primary)),
                  const SizedBox(height: 2),
                  TappableGermanText(_fill(de), isKnown: isKnown, onWordTap: (t) => tap(t, tr)),
                  if (_showTr) Padding(padding: const EdgeInsets.only(top: 2), child: Text(_fill(tr), style: context.text.bodySmall)),
                  if (glossTr != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: InkWell(
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          builder: (_) => Padding(
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
                            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Cümlenin yapısı', style: context.text.titleMedium),
                              const SizedBox(height: 8),
                              Text(_fill(de), style: context.reading),
                              const SizedBox(height: 4),
                              Text(_fill(tr), style: context.text.bodySmall),
                              const SizedBox(height: 12),
                              Text(glossTr, style: context.text.bodyLarge),
                            ]),
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.lightbulb_outline_rounded, size: 16, color: p.accent),
                          const SizedBox(width: 4),
                          Text('Cümleyi açıkla', style: context.text.labelMedium!.copyWith(color: p.accent)),
                        ]),
                      ),
                    ),
                ]),
              ),
              Column(children: [SpeakButton(_fill(de), size: 20), SpeakButton(_fill(de), slow: true, size: 20)]),
            ]),
          ),
        );
      case ChoiceNode(:final choices):
        final chosen = choices.firstWhere((c) => c.id == h?.choiceId, orElse: () => choices.first);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Align(
            alignment: Alignment.centerRight,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(16)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Sen', style: context.text.labelMedium!.copyWith(color: p.accent)),
                      TappableGermanText(_fill(chosen.de), isKnown: isKnown, onWordTap: (t) => tap(t, chosen.tr)),
                      if (_showTr) Text(_fill(chosen.tr), style: context.text.bodySmall),
                    ]),
                  ),
                  SpeakButton(_fill(chosen.de), size: 20),
                ]),
              ),
            ),
          ),
        );
      case BranchNode() || EndNode():
        return const SizedBox.shrink();
    }
  }
}
