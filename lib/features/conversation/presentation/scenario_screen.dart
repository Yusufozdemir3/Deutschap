import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/scenario.dart';
import '../../../core/clock.dart';
import '../../../learning/text/tokenizer.dart';
import '../../../ui/german_text.dart';
import '../../../ui/widgets.dart';
import '../../progress/application/progress_providers.dart';
import '../../vocabulary/domain/vocab_entry.dart';
import '../../vocabulary/presentation/word_sheet.dart';
import '../domain/conversation_engine.dart';
import '../domain/language_issue.dart';

class ScenarioScreen extends ConsumerStatefulWidget {
  const ScenarioScreen({super.key, required this.scenarioId, this.focusEntries});
  final String scenarioId;

  /// Comma-separated entry ids the learner should try to use.
  final String? focusEntries;
  @override
  ConsumerState<ScenarioScreen> createState() => _ScenarioScreenState();
}

class _ScenarioScreenState extends ConsumerState<ScenarioScreen> {
  ConversationState? _state;
  ConversationMode _mode = ConversationMode.guided;
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  String _sessionId = '';
  bool _sending = false;
  bool _hintOpen = false;
  bool _saved = false;
  List<VocabEntry> _focusEntries = const [];

  Scenario? get _scenario => ref.read(contentProvider).scenario(widget.scenarioId);

  @override
  void initState() {
    super.initState();
    final done = ref.read(completedScenariosProvider).valueOrNull ?? const {};
    if (done.contains(widget.scenarioId)) _mode = ConversationMode.practice;
    _loadFocus();
  }

  Future<void> _loadFocus() async {
    final ids = (widget.focusEntries ?? '').split(',').where((s) => s.isNotEmpty);
    final repo = ref.read(vocabRepositoryProvider);
    final out = <VocabEntry>[];
    for (final id in ids) {
      final e = await repo.entry(id);
      if (e != null) out.add(e);
    }
    if (mounted && out.isNotEmpty) setState(() => _focusEntries = out);
  }

  @override
  void dispose() {
    final s = _state;
    if (s != null && !_saved && s.turns.any((t) => t.speaker == Speaker.learner)) {
      // Leaving early keeps the learning signal (corrections), not the transcript.
      _save(s, completed: false);
    }
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _start() {
    final engine = ref.read(conversationEngineProvider);
    _sessionId = ref.read(idGeneratorProvider)();
    setState(() => _state = engine.start(_scenario!, _mode));
  }

  Future<void> _send([String? text]) async {
    final s = _state;
    final msg = (text ?? _input.text).trim();
    if (s == null || msg.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final next = await ref.read(conversationEngineProvider).respond(s, msg);
      if (!mounted) return;
      setState(() {
        _state = next;
        _input.clear();
        _hintOpen = false;
      });
      _scrollDown();
      if (next.isComplete) await _complete(next);
    } catch (e) {
      // The learner's text stays in the field so nothing is lost.
      if (mounted) showToast(context, 'Cevap alınamadı. Mesajın duruyor; tekrar gönderebilirsin.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollDown() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      });

  Future<void> _save(ConversationState s, {required bool completed}) async {
    final keep = ref.read(profileProvider).valueOrNull?.keepTranscripts ?? false;
    await ref.read(progressRepositoryProvider).saveConversation(
          id: _sessionId,
          scenarioId: s.scenario.id,
          mode: s.mode.name,
          completed: completed,
          goalsDone: s.goalsDone.toList(),
          corrections: s.allIssues,
          transcript: keep ? jsonEncode([for (final t in s.turns) t.toJson()]) : null,
        );
  }

  Future<void> _complete(ConversationState s) async {
    _saved = true;
    await _save(s, completed: true);
    // Saved words the learner actually used count as production evidence.
    final lexicon = ref.read(contentProvider).lexicon;
    final repo = ref.read(vocabRepositoryProvider);
    final used = <String, String>{};
    for (final t in s.turns.where((t) => t.speaker == Speaker.learner && t.understood)) {
      final ws = words(t.de);
      final lower = ws.map((w) => w.toLowerCase()).toList();
      for (var i = 0; i < ws.length; i++) {
        for (final l in lexicon.lookupWord(ws[i], sentenceWords: lower, wordIndex: i).lexemes) {
          used.putIfAbsent(l.id, () => t.de);
        }
        for (final m in lexicon.phrasesAt(ws, i)) {
          used.putIfAbsent(m.lexeme.id, () => t.de);
        }
      }
    }
    for (final entry in used.entries) {
      final e = await repo.entryByLexeme(entry.key);
      if (e != null) {
        await repo.recordUsage(e.id, SourceContext(type: SourceType.conversation, sourceId: s.scenario.id, title: s.scenario.titleTr, sentence: entry.value));
      }
    }
    ref.bumpData();
  }

  void _switchMode(ConversationMode m) {
    setState(() {
      _mode = m;
      _state = _state?.copyWith(mode: m);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sc = _scenario;
    if (sc == null) return Scaffold(appBar: AppBar(leading: const BackOrHomeButton()), body: const ErrorState(message: 'Bu senaryo bulunamadı.'));
    final s = _state;
    if (s == null) return _intro(context, sc);
    if (s.isComplete) return _review(context, s);
    return _chat(context, s);
  }

  Widget _intro(BuildContext context, Scenario sc) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton()),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(sc.titleTr, style: context.text.headlineMedium),
              Text(sc.titleDe, style: context.text.titleMedium!.copyWith(fontFamily: 'Literata', color: p.inkMuted)),
              const SizedBox(height: 12),
              Text(sc.settingTr, style: context.text.bodyLarge),
              const SizedBox(height: 4),
              Text('Konuşma ortağın: ${sc.partnerName} · ${sc.partnerRoleTr} · ${sc.formal ? '"Sie" ile' : '"du" ile'}', style: context.text.bodySmall),
              const SectionTitle('Hedefler'),
              for (final g in sc.goals)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(children: [Icon(Icons.flag_outlined, size: 18, color: p.accent), const SizedBox(width: 8), Expanded(child: Text(g.labelTr))]),
                ),
              if (_focusEntries.isNotEmpty) ...[
                const SectionTitle('Kullanmayı dene'),
                Wrap(spacing: 8, runSpacing: 8, children: [for (final e in _focusEntries) Tag(e.headword)]),
              ],
              const SectionTitle('Mod'),
              for (final m in ConversationMode.values)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    onTap: () => setState(() => _mode = m),
                    color: _mode == m ? p.accentSoft : null,
                    borderColor: _mode == m ? p.accent : null,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(m.labelTr, style: context.text.titleSmall),
                          Text(m.descriptionTr, style: context.text.bodySmall),
                        ]),
                      ),
                      Icon(_mode == m ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: _mode == m ? p.accent : p.inkMuted),
                    ]),
                  ),
                ),
              if (sc.disclaimerTr != null) ...[
                const SizedBox(height: 8),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: p.inkMuted),
                  const SizedBox(width: 8),
                  Expanded(child: Text(sc.disclaimerTr!, style: context.text.bodySmall)),
                ]),
              ],
              const SizedBox(height: 8),
              Text('Bu sürümde konuşma ortağı çevrimdışı ve kural tabanlıdır: senaryo hedeflerine uygun cevapları tanır, her cümleyi anlamayabilir. Mesajların cihazdan çıkmaz.', style: context.text.bodySmall),
              const SizedBox(height: 20),
              FilledButton(onPressed: _start, child: const Text('Konuşmayı başlat')),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _chat(BuildContext context, ConversationState s) {
    final p = context.palette;
    final next = s.nextGoal;
    final lastLearner = s.turns.lastIndexWhere((t) => t.speaker == Speaker.learner);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.scenario.partnerName, style: context.text.titleMedium),
        actions: [
          PopupMenuButton<ConversationMode>(
            tooltip: 'Modu değiştir',
            icon: const Icon(Icons.tune_rounded),
            onSelected: _switchMode,
            itemBuilder: (_) => [
              for (final m in ConversationMode.values)
                CheckedPopupMenuItem(value: m, checked: m == s.mode, child: Text(m.labelTr)),
            ],
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final g in s.scenario.goals)
              Pill(
                g.labelTr,
                icon: s.goalsDone.contains(g.id) ? Icons.check_rounded : Icons.flag_outlined,
                color: s.goalsDone.contains(g.id) ? p.successSoft : p.surfaceAlt,
                textColor: s.goalsDone.contains(g.id) ? p.success : p.ink,
              ),
          ]),
        ),
        const Divider(),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            itemCount: s.turns.length,
            itemBuilder: (context, i) => PageWidth(child: _turn(context, s, s.turns[i], showFeedback: s.mode.immediateFeedback && i == lastLearner)),
          ),
        ),
        if (_hintOpen && next != null) _hints(context, next, s.mode),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: PageWidth(
              child: Row(children: [
                if (s.mode.offersHints)
                  IconButton(
                    tooltip: 'İpucu',
                    isSelected: _hintOpen,
                    icon: const Icon(Icons.lightbulb_outline_rounded),
                    selectedIcon: Icon(Icons.lightbulb_rounded, color: p.accent),
                    onPressed: () => setState(() => _hintOpen = !_hintOpen),
                  ),
                Expanded(
                  child: TextField(
                    controller: _input,
                    focusNode: _focus,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.send,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 300,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    style: context.reading.copyWith(fontSize: 17),
                    decoration: const InputDecoration(hintText: 'Almanca yaz…'),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  tooltip: 'Gönder',
                  onPressed: _sending ? null : () => _send(),
                  icon: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.send_rounded),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _hints(BuildContext context, ScenarioGoal g, ConversationMode mode) {
    final p = context.palette;
    return Container(
      width: double.infinity,
      color: p.surfaceAlt,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: PageWidth(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Sıradaki hedef: ${g.labelTr}', style: context.text.labelMedium),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final h in g.hints)
              Tag(
                mode.showsTranslations ? '${h.de}  ·  ${h.tr}' : h.de,
                onTap: () {
                  _input.text = h.de.replaceAll('…', '').trimRight();
                  _focus.requestFocus();
                  _input.selection = TextSelection.collapsed(offset: _input.text.length);
                },
              ),
          ]),
        ]),
      ),
    );
  }

  Widget _turn(BuildContext context, ConversationState s, ConversationTurn t, {required bool showFeedback}) {
    final p = context.palette;
    final partner = t.speaker == Speaker.partner;
    final source = SourceContext(type: SourceType.conversation, sourceId: s.scenario.id, title: s.scenario.titleTr);
    final bubble = Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      decoration: BoxDecoration(
        color: partner ? p.surface : p.accentSoft,
        border: partner ? Border.all(color: p.line) : null,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            TappableGermanText(
              t.de,
              style: context.reading.copyWith(fontSize: 17),
              onWordTap: (tap) => showWordSheet(context, tap: tap, source: source, sentenceTr: partner ? t.tr : null),
            ),
            if (partner && s.mode.showsTranslations && t.tr != null) Text(t.tr!, style: context.text.bodySmall),
          ]),
        ),
        if (partner) SpeakButton(t.de, size: 20) else const SizedBox(width: 8),
      ]),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Column(
        crossAxisAlignment: partner ? CrossAxisAlignment.start : CrossAxisAlignment.end,
        children: [
          ConstrainedBox(constraints: const BoxConstraints(maxWidth: 520), child: bubble),
          if (!partner && showFeedback) _turnFeedback(context, t),
        ],
      ),
    );
  }

  Widget _turnFeedback(BuildContext context, ConversationTurn t) {
    final detailed = ref.read(profileProvider).valueOrNull?.detailedFeedback ?? false;
    final errors = t.issues.where((i) => i.severity == IssueSeverity.error).toList();
    final suggestions = t.issues.where((i) => i.severity == IssueSeverity.suggestion).toList();
    final shown = [...errors.take(detailed ? 5 : 1), ...suggestions.take(detailed ? 3 : (errors.isEmpty ? 1 : 0))];
    if (t.understood && shown.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.check_circle_rounded, size: 16, color: context.palette.success),
          const SizedBox(width: 4),
          Text('Anlaşıldı', style: context.text.labelSmall!.copyWith(color: context.palette.success)),
        ]),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: FeedbackPanel(
          positive: t.understood,
          neutral: t.understood && errors.isEmpty,
          title: t.understood ? (errors.isEmpty ? 'Anlaşıldı · bir öneri' : 'Anlaşıldı ✓ · küçük bir düzeltme') : 'Karşı taraf anlamadı',
          body: t.understood ? null : 'Farklı kelimelerle dene ya da ipucuna bak.',
          extra: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final i in shown) ...[
              Text('${i.kind.labelTr}:', style: context.text.labelMedium),
              if (i.corrected != i.original) Text(i.corrected, style: context.reading.copyWith(fontSize: 16)),
              Text(i.explanationTr, style: context.text.bodySmall),
              const SizedBox(height: 6),
            ],
            if (errors.isNotEmpty)
              TextButton.icon(
                onPressed: () {
                  _input.text = errors.first.corrected;
                  _focus.requestFocus();
                },
                icon: const Icon(Icons.replay_rounded, size: 18),
                label: const Text('Düzeltilmiş hâliyle tekrar söyle'),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _review(BuildContext context, ConversationState s) {
    final p = context.palette;
    final learnerTurns = s.turns.where((t) => t.speaker == Speaker.learner).toList();
    final understood = learnerTurns.where((t) => t.understood).length;
    final seen = <String>{};
    final issues = [for (final i in s.allIssues) if (seen.add('${i.ruleId}|${i.corrected}')) i];
    final lexicon = ref.read(contentProvider).lexicon;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Konuşma özeti')),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.emoji_events_outlined, size: 48, color: p.accent),
              const SizedBox(height: 8),
              Text('Hedefe ulaştın!', style: context.text.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(s.scenario.objectiveTr, style: context.text.bodyMedium, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('• ${learnerTurns.length} mesajın $understood tanesi anlaşıldı.', style: context.text.bodyMedium),
                  Text('• Mod: ${s.mode.labelTr}', style: context.text.bodyMedium),
                  Text('• Düzeltme notu: ${issues.where((i) => i.severity == IssueSeverity.error).length} · öneri: ${issues.where((i) => i.severity == IssueSeverity.suggestion).length}', style: context.text.bodyMedium),
                ]),
              ),
              if (issues.isNotEmpty) ...[
                const SectionTitle('Gözden geçir'),
                for (final i in issues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Pill(i.kind.labelTr, color: i.severity == IssueSeverity.error ? p.dangerSoft : p.accentSoft),
                        const SizedBox(height: 8),
                        if (i.corrected != i.original) ...[
                          Text(i.original, style: context.reading.copyWith(fontSize: 15, decoration: TextDecoration.lineThrough, color: p.inkMuted)),
                          Text(i.corrected, style: context.reading.copyWith(fontSize: 16)),
                          const SizedBox(height: 4),
                        ],
                        Text(i.explanationTr, style: context.text.bodyMedium),
                      ]),
                    ),
                  ),
              ],
              const SectionTitle('Bu durumun kelimeleri'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final id in s.scenario.vocab)
                  if (lexicon.byId(id) case final l?)
                    Tag(l.headword, onTap: () => context.push('/lexeme/${l.id}')),
              ]),
              const SizedBox(height: 8),
              Text('Kullandığın ve defterinde olan kelimeler bu konuşmayla birlikte kaydedildi (aktif kullanım kanıtı).', style: context.text.bodySmall),
              const SizedBox(height: 20),
              FilledButton(onPressed: () => closeOrHome(context), child: const Text('Bitir')),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => setState(() {
                  _saved = false;
                  _state = null;
                  if (_mode == ConversationMode.guided) _mode = ConversationMode.practice;
                }),
                child: const Text('Daha az yardımla tekrar dene'),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
