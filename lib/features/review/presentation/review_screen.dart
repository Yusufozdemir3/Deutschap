import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/clock.dart';
import '../../../learning/answer_checker.dart';
import '../../../ui/widgets.dart';
import '../../vocabulary/domain/vocab_entry.dart';
import '../../vocabulary/domain/vocab_status.dart';
import '../domain/scheduler.dart';

class _Result {
  const _Result(this.item, this.grade, this.assisted, this.after);
  final DueItem item;
  final Grade grade;
  final bool assisted;
  final VocabStatus after;
}

/// A finite review session over due cards. Each card type tests a
/// different skill; hints are allowed and recorded honestly.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, this.size = 10});
  final int size;
  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  List<DueItem>? _items;
  int _i = 0;
  final _results = <_Result>[];
  late String _eventId;
  final _watch = Stopwatch();
  bool _busy = false;

  // per-card UI state
  bool _revealed = false;
  bool _hint = false;
  String? _article;
  final _input = TextEditingController();
  AnswerCheck? _check;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final items = await ref.read(vocabRepositoryProvider).dueItems(limit: widget.size);
    if (!mounted) return;
    setState(() => _items = items);
    _resetCard();
  }

  void _resetCard() {
    _eventId = ref.read(idGeneratorProvider)();
    _revealed = false;
    _hint = false;
    _article = null;
    _check = null;
    _input.clear();
    _watch
      ..reset()
      ..start();
  }

  Future<void> _grade(Grade g) async {
    if (_busy) return;
    _busy = true;
    final item = _items![_i];
    _watch.stop();
    try {
      final out = await ref.read(vocabRepositoryProvider).recordReview(
            eventId: _eventId,
            entryId: item.entry.id,
            type: item.card.type,
            grade: g,
            assisted: _hint,
            latencyMs: _watch.elapsedMilliseconds,
          );
      _results.add(_Result(item, g, _hint, out.after));
      ref.bumpData();
      if (!mounted) return;
      setState(() {
        _i++;
        _resetCard();
      });
    } catch (_) {
      if (mounted) showToast(context, 'Kaydedilemedi. Tekrar dene; cevabın kaybolmadı.');
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items == null) return const Scaffold(body: LoadingView());
    if (items.isEmpty) {
      return Scaffold(
        appBar: AppBar(leading: const BackOrHomeButton()),
        body: EmptyState(
          icon: Icons.task_alt_rounded,
          title: 'Şu an tekrar zamanı gelen kelime yok',
          message: 'Tekrarlar, unutmaya başlamadan hemen önce planlanır. Erken tekrar etmek uzun vadede pek fayda sağlamaz.',
          action: FilledButton(onPressed: () => closeOrHome(context), child: const Text('Tamam')),
        ),
      );
    }
    if (_i >= items.length) return _summary(context);
    final item = items[_i];
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Bitir', onPressed: () => setState(() => _i = items.length)),
        title: Semantics(
          label: 'Kart ${_i + 1} / ${items.length}',
          child: ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: _i / items.length, minHeight: 8)),
        ),
      ),
      body: SafeArea(
        child: KeyedSubtree(
          key: ValueKey(_eventId),
          child: switch (item.card.type) {
            CardType.recognition => _recognition(context, item),
            CardType.production => _production(context, item),
            CardType.article => _articleCard(context, item),
          },
        ),
      ),
    );
  }

  Widget _frame(BuildContext context, {required String label, required List<Widget> body, required Widget actions}) => Column(children: [
        Expanded(
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 16), children: [
            PageWidth(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(label, style: context.text.labelSmall, textAlign: TextAlign.center),
                const SizedBox(height: 20),
                ...body,
              ]),
            ),
          ]),
        ),
        Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 12), child: PageWidth(child: actions)),
      ]);

  Widget _contextBox(BuildContext context, DueItem item) {
    final c = item.context;
    if (c == null || c.sentence.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.palette.surfaceAlt, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${c.type.labelTr}${c.title != null ? ' · ${c.title}' : ''}', style: context.text.labelSmall),
        const SizedBox(height: 4),
        Text(c.sentence, style: context.reading.copyWith(fontSize: 16)),
        if (c.sentenceTr != null && _revealed) Text(c.sentenceTr!, style: context.text.bodySmall),
      ]),
    );
  }

  Widget _gradeButtons(BuildContext context) {
    final p = context.palette;
    Widget b(String label, Grade g, Color c) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: c, side: BorderSide(color: c.withValues(alpha: 0.6), width: 1.5), padding: const EdgeInsets.symmetric(horizontal: 4)),
              onPressed: () => _grade(g),
              child: Text(label, textAlign: TextAlign.center),
            ),
          ),
        );
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Text('Ne kadar iyi hatırladın?', style: context.text.labelSmall),
      const SizedBox(height: 6),
      Row(children: [
        b('Hatırlamadım', Grade.again, p.danger),
        b('Zorlandım', Grade.hard, p.accent),
        b('Hatırladım', Grade.good, p.success),
        b('Çok kolay', Grade.easy, p.primary),
      ]),
    ]);
  }

  Widget _recognition(BuildContext context, DueItem item) {
    final e = item.entry;
    final lemma = e.article != null && e.headword.startsWith('${e.article} ') ? e.headword.substring(e.article!.length + 1) : e.headword;
    return _frame(
      context,
      label: 'ANLAMINI HATIRLA',
      body: [
        Center(child: Headword(lemma: lemma, article: e.article, style: context.text.displaySmall!.copyWith(fontFamily: 'Literata'))),
        Center(child: SpeakButton(e.headword, size: 28)),
        if (_revealed) ...[
          const SizedBox(height: 12),
          Text(e.meaningTr, style: context.text.headlineSmall, textAlign: TextAlign.center),
          if (e.plural != null && e.plural != '—') Text('Çoğul: ${e.plural}', style: context.text.bodySmall, textAlign: TextAlign.center),
        ],
        if (_revealed || _hint) _contextBox(context, item),
      ],
      actions: _revealed
          ? _gradeButtons(context)
          : Column(mainAxisSize: MainAxisSize.min, children: [
              if (!_hint && item.context != null && item.context!.sentence.isNotEmpty)
                TextButton.icon(onPressed: () => setState(() => _hint = true), icon: const Icon(Icons.lightbulb_outline_rounded), label: const Text('Cümle ipucu')),
              SizedBox(width: double.infinity, child: FilledButton(onPressed: () => setState(() => _revealed = true), child: const Text('Anlamı göster'))),
            ]),
    );
  }

  Widget _production(BuildContext context, DueItem item) {
    final e = item.entry;
    final accepted = <String>[e.headword, if (e.lemma != e.headword) e.lemma];
    final checked = _check != null;
    Grade autoGrade() {
      final c = _check!;
      if (e.article != null && c.verdict == AnswerVerdict.correct && normalizeAnswer(_input.text).toLowerCase() == e.lemma.toLowerCase()) return Grade.hard;
      return switch (c.verdict) {
        AnswerVerdict.correct || AnswerVerdict.correctWithNote => Grade.good,
        AnswerVerdict.nearMiss => Grade.hard,
        AnswerVerdict.wrong => Grade.again,
      };
    }

    final missingArticle = checked && e.article != null && normalizeAnswer(_input.text).toLowerCase() == e.lemma.toLowerCase();
    return _frame(
      context,
      label: 'ALMANCASINI YAZ',
      body: [
        Text(e.meaningTr, style: context.text.headlineSmall, textAlign: TextAlign.center),
        if (e.isNoun) Text('İsimse artikeliyle yaz (der/die/das …)', style: context.text.bodySmall, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        TextField(
          controller: _input,
          enabled: !checked,
          autocorrect: false,
          enableSuggestions: false,
          textAlign: TextAlign.center,
          style: context.reading.copyWith(fontSize: 22),
          decoration: const InputDecoration(hintText: '…'),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => _input.text.trim().isEmpty ? null : setState(() => _check = checkAnswer(_input.text, accepted)),
        ),
        if (_hint && !checked) Padding(padding: const EdgeInsets.only(top: 8), child: Text('İlk harfler: ${e.lemma.substring(0, e.lemma.length < 3 ? 1 : 2)}…', textAlign: TextAlign.center)),
        if (checked) ...[
          const SizedBox(height: 16),
          FeedbackPanel(
            positive: _check!.verdict.isAccepted,
            neutral: missingArticle || _check!.verdict == AnswerVerdict.nearMiss,
            title: missingArticle ? 'Kelime doğru – artikeli unutma' : (_check!.verdict.isAccepted ? 'Doğru!' : 'Doğrusu:'),
            body: [e.headword, ?_check!.noteTr].join('\n'),
            extra: Align(alignment: Alignment.centerLeft, child: SpeakButton(e.headword)),
          ),
          _contextBox(context, item),
        ],
      ],
      actions: checked
          ? SizedBox(width: double.infinity, child: FilledButton(onPressed: () => _grade(autoGrade()), child: const Text('Devam')))
          : Column(mainAxisSize: MainAxisSize.min, children: [
              if (!_hint) TextButton.icon(onPressed: () => setState(() => _hint = true), icon: const Icon(Icons.lightbulb_outline_rounded), label: const Text('İpucu')),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() {
                      _input.text = '';
                      _check = const AnswerCheck(AnswerVerdict.wrong, '');
                    }),
                    child: const Text('Bilmiyorum'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _input.text.trim().isEmpty ? null : () => setState(() => _check = checkAnswer(_input.text, accepted)),
                    child: const Text('Kontrol et'),
                  ),
                ),
              ]),
            ]),
    );
  }

  Widget _articleCard(BuildContext context, DueItem item) {
    final e = item.entry;
    final p = context.palette;
    final lemma = e.lemma;
    final picked = _article;
    final correct = picked == e.article;
    return _frame(
      context,
      label: 'ARTİKELİ SEÇ',
      body: [
        Center(child: Text(picked == null ? '___ $lemma' : '${e.article} $lemma', style: context.text.displaySmall!.copyWith(fontFamily: 'Literata'))),
        const SizedBox(height: 4),
        Text(e.meaningTr, style: context.text.bodyLarge!.copyWith(color: p.inkMuted), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Row(children: [
          for (final a in const ['der', 'die', 'das'])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: AppCard(
                  onTap: picked == null ? () => setState(() => _article = a) : null,
                  color: picked == null ? null : (a == e.article ? p.successSoft : (a == picked ? p.dangerSoft : null)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  semanticLabel: a,
                  child: Center(child: Text(a, style: context.text.titleLarge!.copyWith(color: p.article(a)))),
                ),
              ),
            ),
        ]),
        if (picked != null) ...[
          const SizedBox(height: 16),
          FeedbackPanel(positive: correct, title: correct ? 'Doğru: ${e.headword}' : 'Doğrusu: ${e.headword}', body: e.plural != null && e.plural != '—' ? 'Çoğul: ${e.plural}' : null),
          _contextBox(context, item),
        ],
      ],
      actions: SizedBox(
        width: double.infinity,
        child: FilledButton(onPressed: picked == null ? null : () => _grade(correct ? Grade.good : Grade.again), child: const Text('Devam')),
      ),
    );
  }

  Widget _summary(BuildContext context) {
    final p = context.palette;
    final unaided = _results.where((r) => r.grade.isSuccess && !r.assisted).length;
    final assisted = _results.where((r) => r.grade.isSuccess && r.assisted).length;
    final missed = _results.where((r) => !r.grade.isSuccess).toList();
    final production = _results.where((r) => r.item.card.type == CardType.production && r.grade.isSuccess && !r.assisted).length;
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Kapat', onPressed: () => closeOrHome(context))),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.check_circle_rounded, size: 52, color: p.success),
              const SizedBox(height: 8),
              Text('Tekrar tamamlandı', style: context.text.headlineSmall, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              if (_results.isEmpty)
                Text('Bu oturumda kart cevaplamadın. Sorun değil – kartlar seni bekliyor.', style: context.text.bodyMedium, textAlign: TextAlign.center)
              else
                AppCard(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('• $unaided kartı ipucusuz hatırladın.', style: context.text.bodyLarge),
                    if (production > 0) Text('• Bunların $production tanesinde Almancasını kendin yazdın.', style: context.text.bodyLarge),
                    if (assisted > 0) Text('• $assisted kartı ipucuyla hatırladın (daha kısa aralıkla tekrar gelecek).', style: context.text.bodyLarge),
                    if (missed.isNotEmpty) Text('• ${missed.length} kart yakında tekrar gelecek.', style: context.text.bodyLarge),
                    const SizedBox(height: 8),
                    Text('Bu bir anlık sonuç. Kalıcılık, günler sonraki tekrarlarda görünür.', style: context.text.bodySmall),
                  ]),
                ),
              if (missed.isNotEmpty) ...[
                const SectionTitle('Pekiştirilecekler'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final m in missed) Tag(m.item.entry.headword, onTap: () => context.push('/word/${m.item.entry.id}')),
                ]),
              ],
              const SizedBox(height: 24),
              FilledButton(onPressed: () => closeOrHome(context), child: const Text('Bitir')),
            ]),
          ),
        ],
      ),
    );
  }
}
