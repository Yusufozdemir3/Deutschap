import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/lesson.dart';
import '../../../core/audio/speech_service.dart';
import '../../../learning/answer_checker.dart';
import '../../../learning/text/tokenizer.dart';
import '../../../ui/german_text.dart';
import '../../../ui/widgets.dart';
import '../../conversation/domain/error_detectors.dart';
import '../../conversation/domain/language_issue.dart';
import '../../grammar/presentation/grammar_view.dart';
import '../../vocabulary/domain/vocab_entry.dart';
import '../../vocabulary/presentation/word_sheet.dart';

/// Result of a graded step. [assisted] means a hint was used.
class StepOutcome {
  const StepOutcome({required this.correct, this.assisted = false});
  final bool correct;
  final bool assisted;
}

typedef StepDone = void Function(StepOutcome? outcome);

/// Shared frame for a step: content plus a sticky action button.
class StepFrame extends StatelessWidget {
  const StepFrame({super.key, required this.children, required this.action});
  final List<Widget> children;
  final Widget action;
  @override
  Widget build(BuildContext context) => Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [PageWidth(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children))],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: PageWidth(child: SizedBox(width: double.infinity, child: action)),
            ),
          ),
        ],
      );
}

/// Graded steps share the check → feedback → continue rhythm.
mixin _Checkable<T extends StatefulWidget> on State<T> {
  bool checked = false;
  bool correct = false;
  bool assisted = false;
  String? note;

  StepDone get done;
  bool get canCheck;
  void evaluate();

  void check() => setState(() {
        evaluate();
        checked = true;
      });

  Widget actionButton() => FilledButton(
        onPressed: !checked ? (canCheck ? check : null) : () => done(StepOutcome(correct: correct, assisted: assisted)),
        child: Text(checked ? 'Devam' : 'Kontrol et'),
      );
}

// ---------------------------------------------------------------- intro

class IntroStepView extends ConsumerWidget {
  const IntroStepView({super.key, required this.step, required this.lesson, required this.done});
  final IntroStep step;
  final Lesson lesson;
  final StepDone done;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lexicon = ref.watch(contentProvider).lexicon;
    return StepFrame(
      action: FilledButton(onPressed: () => done(null), child: const Text('Devam')),
      children: [
        Text('Yeni kelimeler', style: context.text.headlineSmall),
        const SizedBox(height: 4),
        Text(step.noteTr ?? 'Dinle ve tekrar et. Kaydettiklerin kelime defterine örnek cümlesiyle girer.', style: context.text.bodySmall),
        const SizedBox(height: 14),
        for (final id in step.lexemes)
          if (lexicon.byId(id) case final l?)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: LexemeCard(
                lexeme: l,
                context_: SourceContext(
                  type: SourceType.lesson,
                  sourceId: lesson.id,
                  title: lesson.titleTr,
                  sentence: l.examples.isEmpty ? '' : l.examples.first.de,
                  sentenceTr: l.examples.isEmpty ? null : l.examples.first.tr,
                ),
              ),
            ),
      ],
    );
  }
}

// -------------------------------------------------------------- grammar

class GrammarStepView extends ConsumerWidget {
  const GrammarStepView({super.key, required this.step, required this.done});
  final GrammarStep step;
  final StepDone done;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(contentProvider).grammar[step.conceptId];
    return StepFrame(
      action: FilledButton(onPressed: () => done(null), child: const Text('Anladım, devam')),
      children: [if (c != null) GrammarConceptView(concept: c) else const Text('Konu bulunamadı.')],
    );
  }
}

// ------------------------------------------------------------- dialogue

class DialogueStepView extends ConsumerStatefulWidget {
  const DialogueStepView({super.key, required this.step, required this.lesson, required this.done});
  final DialogueStep step;
  final Lesson lesson;
  final StepDone done;
  @override
  ConsumerState<DialogueStepView> createState() => _DialogueStepViewState();
}

class _DialogueStepViewState extends ConsumerState<DialogueStepView> {
  static const _pitches = [1.0, 0.8, 1.2, 0.9];
  bool _showTr = false;
  bool _playing = false;
  int? _current;
  int _token = 0;
  late final SpeechService _speech;

  @override
  void initState() {
    super.initState();
    _speech = ref.read(speechServiceProvider);
  }

  @override
  void dispose() {
    _token++;
    _speech.stop();
    super.dispose();
  }

  /// Plays the whole dialogue, one pitch per speaker.
  Future<void> _playAll() async {
    final lines = widget.step.lines;
    final speakers = {for (final l in lines) l.speaker}.toList();
    final token = ++_token;
    setState(() => _playing = true);
    for (var i = 0; i < lines.length; i++) {
      if (!mounted || token != _token) return;
      setState(() => _current = i);
      final ok = await _speech.speak(lines[i].de, wait: true, pitch: _pitches[speakers.indexOf(lines[i].speaker) % _pitches.length]);
      if (!ok) {
        if (mounted) showToast(context, 'Bu cihazda Almanca ses bulunamadı. Metin her zaman görünür kalır.');
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    if (mounted && token == _token) {
      setState(() {
        _playing = false;
        _current = null;
      });
    }
  }

  void _stop() {
    _token++;
    _speech.stop();
    setState(() {
      _playing = false;
      _current = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return StepFrame(
      action: FilledButton(onPressed: () => widget.done(null), child: const Text('Devam')),
      children: [
        Row(children: [
          Expanded(child: Text(widget.step.titleTr ?? 'Diyalog', style: context.text.headlineSmall)),
          TextButton.icon(
            onPressed: () => setState(() => _showTr = !_showTr),
            icon: Icon(_showTr ? Icons.visibility_off_outlined : Icons.translate_rounded),
            label: Text(_showTr ? 'Çeviriyi gizle' : 'Çeviri'),
          ),
        ]),
        Text('Kelimelere dokunarak anlamlarını görebilirsin.', style: context.text.bodySmall),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: _playing ? _stop : _playAll,
            icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
            label: Text(_playing ? 'Durdur' : 'Hepsini dinle'),
          ),
        ),
        const SizedBox(height: 12),
        for (final (index, line) in widget.step.lines.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Align(
              alignment: line.speaker == 'Du' ? Alignment.centerRight : Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                  decoration: BoxDecoration(
                    color: _current == index ? p.accentSoft : (line.speaker == 'Du' ? p.accentSoft : p.surface),
                    border: Border.all(color: _current == index ? p.accent : p.line),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(line.speaker == 'Du' ? 'Sen' : line.speaker, style: context.text.labelSmall),
                        const SizedBox(height: 2),
                        TappableGermanText(
                          line.de,
                          style: context.reading.copyWith(fontSize: 17),
                          onWordTap: (tap) => showWordSheet(
                            context,
                            tap: tap,
                            sentenceTr: line.tr,
                            source: SourceContext(type: SourceType.lesson, sourceId: widget.lesson.id, title: widget.lesson.titleTr),
                          ),
                        ),
                        if (_showTr) Text(line.tr, style: context.text.bodySmall),
                      ]),
                    ),
                    SpeakButton(line.de, size: 20),
                  ]),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// --------------------------------------------------------------- choice

class ChoiceStepView extends StatefulWidget {
  const ChoiceStepView({super.key, required this.step, required this.done});
  final ChoiceStep step;
  final StepDone done;
  @override
  State<ChoiceStepView> createState() => _ChoiceStepViewState();
}

class _ChoiceStepViewState extends State<ChoiceStepView> with _Checkable {
  int? _picked;
  late final _order = optionOrder(widget.step.options.length, widget.step.id);
  @override
  StepDone get done => widget.done;
  @override
  bool get canCheck => _picked != null;
  @override
  void evaluate() => correct = widget.step.answers.contains(_picked);

  @override
  Widget build(BuildContext context) {
    final s = widget.step;
    return StepFrame(
      action: actionButton(),
      children: [
        Text(s.promptTr, style: context.text.titleLarge),
        if (s.de != null) ...[
          const SizedBox(height: 12),
          Row(children: [Expanded(child: Text(s.de!, style: context.reading)), SpeakButton(s.de!.replaceAll('___', '…'))]),
        ],
        const SizedBox(height: 16),
        for (final i in _order)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OptionTile(
              label: s.options[i],
              selected: _picked == i,
              state: !checked ? null : (s.answers.contains(i) ? true : (_picked == i ? false : null)),
              onTap: checked ? null : () => setState(() => _picked = i),
            ),
          ),
        if (checked) ...[
          const SizedBox(height: 8),
          FeedbackPanel(positive: correct, title: correct ? 'Doğru!' : 'Tam olarak değil', body: s.explainTr),
        ],
      ],
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.label, required this.selected, required this.onTap, this.state});
  final String label;
  final bool selected;
  final bool? state;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final color = state == true ? p.successSoft : (state == false ? p.dangerSoft : (selected ? p.accentSoft : null));
    final border = state == true ? p.success : (state == false ? p.danger : (selected ? p.accent : null));
    final icon = state == true ? Icons.check_rounded : (state == false ? Icons.close_rounded : null);
    return Semantics(
      selected: selected,
      label: state == true ? '$label, doğru cevap' : (state == false ? '$label, yanlış' : label),
      excludeSemantics: true,
      child: AppCard(
        onTap: onTap,
        color: color,
        borderColor: border,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(children: [
          Expanded(child: Text(label, style: context.reading.copyWith(fontSize: 17))),
          if (icon != null) Icon(icon, color: border),
        ]),
      ),
    );
  }
}

// -------------------------------------------------------------- article

class ArticleStepView extends ConsumerStatefulWidget {
  const ArticleStepView({super.key, required this.step, required this.done});
  final ArticleStep step;
  final StepDone done;
  @override
  ConsumerState<ArticleStepView> createState() => _ArticleStepViewState();
}

class _ArticleStepViewState extends ConsumerState<ArticleStepView> with _Checkable {
  String? _picked;
  @override
  StepDone get done => widget.done;
  @override
  bool get canCheck => _picked != null;
  @override
  void evaluate() => correct = _picked == ref.read(contentProvider).lexicon.byId(widget.step.lexemeId)?.article;

  @override
  Widget build(BuildContext context) {
    final l = ref.watch(contentProvider).lexicon.byId(widget.step.lexemeId)!;
    final p = context.palette;
    return StepFrame(
      action: actionButton(),
      children: [
        Text('Artikeli seç', style: context.text.titleLarge),
        const SizedBox(height: 4),
        Text(l.tr, style: context.text.bodyMedium!.copyWith(color: p.inkMuted)),
        const SizedBox(height: 28),
        Center(child: Text(checked ? l.headword : '___ ${l.lemma}', style: context.text.displaySmall!.copyWith(fontFamily: 'Literata'))),
        const SizedBox(height: 28),
        Row(children: [
          for (final a in const ['der', 'die', 'das'])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _OptionTile(
                  label: a,
                  selected: _picked == a,
                  state: !checked ? null : (a == l.article ? true : (_picked == a ? false : null)),
                  onTap: checked ? null : () => setState(() => _picked = a),
                ),
              ),
            ),
        ]),
        if (checked) ...[
          const SizedBox(height: 16),
          FeedbackPanel(
            positive: correct,
            title: correct ? 'Doğru: ${l.headword}' : 'Doğrusu: ${l.headword}',
            body: [
              if (l.plural != null && l.plural != '—') 'Çoğul: ${l.plural}',
              ?l.noteTr,
            ].join('\n'),
            extra: Align(alignment: Alignment.centerLeft, child: SpeakButton(l.headword)),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- cloze

class ClozeStepView extends StatefulWidget {
  const ClozeStepView({super.key, required this.step, required this.done});
  final ClozeStep step;
  final StepDone done;
  @override
  State<ClozeStepView> createState() => _ClozeStepViewState();
}

class _ClozeStepViewState extends State<ClozeStepView> with _Checkable {
  String? _picked;
  final _input = TextEditingController();
  AnswerCheck? _check;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool get _typed => widget.step.options.isEmpty;
  @override
  StepDone get done => widget.done;
  @override
  bool get canCheck => _typed ? _input.text.trim().isNotEmpty : _picked != null;
  @override
  void evaluate() {
    _check = checkAnswer(_typed ? _input.text : _picked!, widget.step.answers);
    correct = _check!.verdict.isAccepted;
    note = _check!.noteTr;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.step;
    final parts = s.de.split('___');
    final filled = checked ? (_typed ? _check!.expected : (correct ? _picked! : s.answers.first)) : (_typed ? '…' : (_picked ?? '…'));
    final p = context.palette;
    return StepFrame(
      action: actionButton(),
      children: [
        Text('Boşluğu doldur', style: context.text.titleLarge),
        const SizedBox(height: 4),
        Text(s.tr, style: context.text.bodyMedium!.copyWith(color: p.inkMuted)),
        const SizedBox(height: 24),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: parts.first),
            TextSpan(text: filled, style: TextStyle(color: p.primary, decoration: TextDecoration.underline, decorationColor: p.primary)),
            if (parts.length > 1) TextSpan(text: parts[1]),
          ]),
          style: context.reading.copyWith(fontSize: 22),
        ),
        const SizedBox(height: 24),
        if (_typed)
          TextField(
            controller: _input,
            enabled: !checked,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(hintText: 'Cevabını yaz'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (canCheck && !checked) check();
            },
          )
        else
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final o in s.options)
              ChoiceChip(
                label: Text(o, style: context.reading.copyWith(fontSize: 17)),
                selected: _picked == o,
                onSelected: checked ? null : (_) => setState(() => _picked = o),
              ),
          ]),
        if (checked) ...[
          const SizedBox(height: 16),
          FeedbackPanel(
            positive: correct,
            title: correct ? (note == null ? 'Doğru!' : 'Kabul edildi') : 'Doğrusu: ${s.answers.first}',
            body: [?note, s.explainTr].join('\n\n'),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- order

class OrderStepView extends StatefulWidget {
  const OrderStepView({super.key, required this.step, required this.done});
  final OrderStep step;
  final StepDone done;
  @override
  State<OrderStepView> createState() => _OrderStepViewState();
}

class _OrderStepViewState extends State<OrderStepView> with _Checkable {
  late final List<int> _pool;
  final _built = <int>[];

  @override
  void initState() {
    super.initState();
    _pool = List.generate(widget.step.tokens.length, (i) => i)..shuffle(Random(widget.step.id.hashCode));
    if (_pool.length > 1 && _isIdentity(_pool)) _pool.insert(0, _pool.removeLast());
  }

  static bool _isIdentity(List<int> l) {
    for (var i = 0; i < l.length; i++) {
      if (l[i] != i) return false;
    }
    return true;
  }

  String get _sentence => _built.map((i) => widget.step.tokens[i]).join(' ');

  @override
  StepDone get done => widget.done;
  @override
  bool get canCheck => _built.length == widget.step.tokens.length;
  @override
  void evaluate() {
    // Order is what is tested; capitalisation of the first word is not.
    final mine = fold(_sentence);
    correct = widget.step.answers.any((a) => fold(normalizeAnswer(a)) == mine);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.step;
    final p = context.palette;
    return StepFrame(
      action: actionButton(),
      children: [
        Text('Cümleyi kur', style: context.text.titleLarge),
        const SizedBox(height: 4),
        Text(s.tr, style: context.text.bodyLarge!.copyWith(color: p.inkMuted)),
        const SizedBox(height: 20),
        Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: p.line, width: 2)),
          ),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final i in _built)
              ActionChip(
                label: Text(s.tokens[i], style: context.reading.copyWith(fontSize: 17)),
                onPressed: checked ? null : () => setState(() => _built.remove(i)),
                tooltip: 'Çıkar',
              ),
          ]),
        ),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final i in _pool)
            if (!_built.contains(i))
              ActionChip(
                label: Text(s.tokens[i], style: context.reading.copyWith(fontSize: 17)),
                onPressed: checked ? null : () => setState(() => _built.add(i)),
              ),
        ]),
        if (checked) ...[
          const SizedBox(height: 16),
          FeedbackPanel(
            positive: correct,
            title: correct ? 'Doğru!' : 'Doğrusu: ${s.answers.first}',
            body: [
              if (s.answers.length > 1) 'Kabul edilen sıralar: ${s.answers.join(' · ')}',
              ?s.explainTr,
            ].join('\n'),
            extra: Align(alignment: Alignment.centerLeft, child: SpeakButton(s.answers.first)),
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------ translate

class TranslateStepView extends StatefulWidget {
  const TranslateStepView({super.key, required this.step, required this.done});
  final TranslateStep step;
  final StepDone done;
  @override
  State<TranslateStepView> createState() => _TranslateStepViewState();
}

class _TranslateStepViewState extends State<TranslateStepView> with _Checkable {
  final _input = TextEditingController();
  bool _hint = false;
  AnswerCheck? _check;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  StepDone get done => widget.done;
  @override
  bool get canCheck => _input.text.trim().isNotEmpty;
  @override
  void evaluate() {
    _check = checkAnswer(_input.text, widget.step.answers);
    correct = _check!.verdict.isAccepted;
    assisted = _hint;
    note = _check!.noteTr;
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.step;
    final p = context.palette;
    return StepFrame(
      action: actionButton(),
      children: [
        Text('Almancaya çevir', style: context.text.titleLarge),
        const SizedBox(height: 16),
        AppCard(child: Text(s.tr, style: context.text.titleMedium)),
        const SizedBox(height: 16),
        TextField(
          controller: _input,
          enabled: !checked,
          autocorrect: false,
          enableSuggestions: false,
          minLines: 1,
          maxLines: 3,
          style: context.reading.copyWith(fontSize: 18),
          decoration: const InputDecoration(hintText: 'Almanca yaz…'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        if (s.hintTr != null && !checked)
          Align(
            alignment: Alignment.centerLeft,
            child: _hint
                ? Text('İpucu: ${s.hintTr}', style: context.text.bodyMedium!.copyWith(color: p.accent))
                : TextButton.icon(onPressed: () => setState(() => _hint = true), icon: const Icon(Icons.lightbulb_outline_rounded), label: const Text('İpucu')),
          ),
        Text('ä, ö, ü, ß yazamıyorsan ae, oe, ue, ss da olur.', style: context.text.bodySmall),
        if (checked) ...[
          const SizedBox(height: 16),
          FeedbackPanel(
            positive: correct,
            title: switch (_check!.verdict) {
              AnswerVerdict.correct => 'Doğru!',
              AnswerVerdict.correctWithNote => 'Kabul edildi',
              AnswerVerdict.nearMiss => 'Neredeyse!',
              AnswerVerdict.wrong => 'Örnek bir doğru cevap:',
            },
            body: [
              if (_check!.verdict == AnswerVerdict.wrong) _check!.expected,
              ?note,
              if (s.answers.length > 1) 'Başka doğru cevaplar da var: ${s.answers.where((a) => a != _check!.expected).take(2).join(' · ')}',
              ?s.explainTr,
            ].join('\n\n'),
            extra: Align(alignment: Alignment.centerLeft, child: SpeakButton(_check!.expected)),
          ),
        ],
      ],
    );
  }
}

// --------------------------------------------------------------- listen

class ListenStepView extends ConsumerStatefulWidget {
  const ListenStepView({super.key, required this.step, required this.done});
  final ListenStep step;
  final StepDone done;
  @override
  ConsumerState<ListenStepView> createState() => _ListenStepViewState();
}

class _ListenStepViewState extends ConsumerState<ListenStepView> with _Checkable {
  int? _picked;
  late final _order = optionOrder(widget.step.options.length, widget.step.id);
  bool _textShown = false;
  bool _noVoice = false;

  @override
  StepDone get done => widget.done;
  @override
  bool get canCheck => _picked != null;
  @override
  void evaluate() {
    correct = widget.step.answers.contains(_picked);
    // Reading the text instead of listening is fine, but it is help;
    // without a voice there was no other option, so it is not counted.
    assisted = _textShown && !_noVoice;
  }

  Future<void> _play({bool slow = false}) async {
    final ok = await ref.read(speechServiceProvider).speak(widget.step.de, slow: slow);
    if (!ok && mounted) setState(() => _noVoice = _textShown = true);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _play());
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.step;
    final p = context.palette;
    return StepFrame(
      action: actionButton(),
      children: [
        Text('Dinle ve anla', style: context.text.titleLarge),
        const SizedBox(height: 20),
        Center(
          child: Wrap(spacing: 12, children: [
            FilledButton.icon(onPressed: _play, icon: const Icon(Icons.volume_up_rounded), label: const Text('Dinle')),
            OutlinedButton.icon(onPressed: () => _play(slow: true), icon: const Icon(Icons.slow_motion_video_rounded), label: const Text('Yavaş')),
          ]),
        ),
        const SizedBox(height: 12),
        if (_textShown || checked)
          AppCard(color: p.surfaceAlt, child: Text(s.de, style: context.reading))
        else
          Center(
            child: TextButton(onPressed: () => setState(() => _textShown = true), child: const Text('Duyamıyorum – metni göster')),
          ),
        if (_noVoice) Text('Bu cihazda Almanca ses bulunamadı, metni okuyarak devam edebilirsin.', style: context.text.bodySmall),
        const SizedBox(height: 16),
        Text(s.promptTr, style: context.text.titleMedium),
        const SizedBox(height: 10),
        for (final i in _order)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _OptionTile(
              label: s.options[i],
              selected: _picked == i,
              state: !checked ? null : (s.answers.contains(i) ? true : (_picked == i ? false : null)),
              onTap: checked ? null : () => setState(() => _picked = i),
            ),
          ),
        if (checked) FeedbackPanel(positive: correct, title: correct ? 'Doğru anladın!' : 'Tam olarak değil', body: s.explainTr),
      ],
    );
  }
}

// ---------------------------------------------------------------- write

class WriteStepView extends ConsumerStatefulWidget {
  const WriteStepView({super.key, required this.step, required this.done});
  final WriteStep step;
  final StepDone done;
  @override
  ConsumerState<WriteStepView> createState() => _WriteStepViewState();
}

class _WriteStepViewState extends ConsumerState<WriteStepView> with _Checkable {
  final _input = TextEditingController();
  List<(WriteRequirement, bool)> _reqs = const [];
  List<LanguageIssue> _issues = const [];
  int _words = 0;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  StepDone get done => widget.done;
  @override
  bool get canCheck => _input.text.trim().isNotEmpty;
  @override
  void evaluate() {
    final text = _input.text.trim();
    final folded = fold(text);
    _words = words(text).length;
    _reqs = [for (final r in widget.step.requirements) (r, RegExp(r.pattern).hasMatch(folded))];
    _issues = ErrorDetectors(ref.read(contentProvider).lexicon).check(text, serviceContext: true);
    correct = _reqs.every((r) => r.$2) && _words >= widget.step.minWords && !_issues.any((i) => i.severity == IssueSeverity.error);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.step;
    final p = context.palette;
    Widget line(bool ok, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: ok ? p.success : p.danger),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: context.text.bodyMedium)),
          ]),
        );
    return StepFrame(
      action: actionButton(),
      children: [
        Text('Kendin yaz', style: context.text.titleLarge),
        const SizedBox(height: 8),
        AppCard(child: Text(s.promptTr, style: context.text.bodyLarge)),
        const SizedBox(height: 14),
        TextField(
          controller: _input,
          enabled: !checked,
          autocorrect: false,
          enableSuggestions: false,
          minLines: 2,
          maxLines: 5,
          maxLength: 400,
          style: context.reading.copyWith(fontSize: 18),
          decoration: const InputDecoration(hintText: 'Almanca yaz…'),
          onChanged: (_) => setState(() {}),
        ),
        if (checked) ...[
          const SizedBox(height: 8),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Görev', style: context.text.titleSmall),
              const SizedBox(height: 6),
              for (final (r, ok) in _reqs) line(ok, r.labelTr),
              line(_words >= s.minWords, 'En az ${s.minWords} kelime ($_words)'),
              const Divider(height: 24),
              Text('Dil', style: context.text.titleSmall),
              const SizedBox(height: 6),
              if (_issues.isEmpty)
                Text('Otomatik kontrol bir hata bulmadı. Bu kontrol sadece sık yapılan bazı hatalara bakar; her hatayı yakalamaz.', style: context.text.bodySmall)
              else
                for (final i in _issues) ...[
                  Text('${i.kind.labelTr}${i.severity == IssueSeverity.suggestion ? ' (öneri)' : ''}', style: context.text.labelMedium),
                  if (i.corrected != i.original) Text(i.corrected, style: context.reading.copyWith(fontSize: 16)),
                  Text(i.explanationTr, style: context.text.bodySmall),
                  const SizedBox(height: 6),
                ],
              const Divider(height: 24),
              Text('Örnek bir cevap', style: context.text.titleSmall),
              const SizedBox(height: 4),
              Row(children: [Expanded(child: Text(s.model, style: context.reading.copyWith(fontSize: 17))), SpeakButton(s.model, size: 20)]),
              Text('Senin cevabın farklı ama yine de doğru olabilir.', style: context.text.bodySmall),
            ]),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- match

/// Tap a German item, then its meaning. Correct pairs lock; a wrong pair
/// is shown briefly and counted. The step counts as correct with no
/// mistakes; the learner always finishes the board.
class MatchStepView extends ConsumerStatefulWidget {
  const MatchStepView({super.key, required this.step, required this.done, this.seed = 0});
  final MatchStep step;
  final StepDone done;
  final int seed;
  @override
  ConsumerState<MatchStepView> createState() => _MatchStepViewState();
}

class _MatchStepViewState extends ConsumerState<MatchStepView> {
  late final List<int> _left;
  late final List<int> _right;
  final _matched = <int>{};
  int? _pickLeft;
  int? _pickRight;
  (int, int)? _wrong;
  int _mistakes = 0;

  @override
  void initState() {
    super.initState();
    final n = widget.step.pairs.length;
    final rnd = Random(widget.seed ^ widget.step.id.hashCode);
    _left = List.generate(n, (i) => i)..shuffle(rnd);
    _right = List.generate(n, (i) => i)..shuffle(rnd);
  }

  bool get _complete => _matched.length == widget.step.pairs.length;

  void _tryPair() {
    final l = _pickLeft, r = _pickRight;
    if (l == null || r == null) return;
    if (l == r) {
      _matched.add(l);
      _pickLeft = _pickRight = null;
      ref.read(speechServiceProvider).speak(widget.step.pairs[l].de);
    } else {
      _mistakes++;
      _wrong = (l, r);
      _pickLeft = _pickRight = null;
      Future.delayed(const Duration(milliseconds: 700), () {
        if (mounted) setState(() => _wrong = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.step;
    final p = context.palette;
    Widget tile(String label, {required bool done, required bool selected, required bool wrong, required VoidCallback onTap, bool german = false}) {
      final color = done ? p.successSoft : (wrong ? p.dangerSoft : (selected ? p.accentSoft : null));
      final border = done ? p.success : (wrong ? p.danger : (selected ? p.accent : null));
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Semantics(
          button: !done,
          selected: selected,
          label: done ? '$label, eşleşti' : label,
          excludeSemantics: true,
          child: AppCard(
            onTap: done ? null : onTap,
            color: color,
            borderColor: border,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            child: Text(label, style: german ? context.reading.copyWith(fontSize: 16) : context.text.bodyMedium, textAlign: TextAlign.center),
          ),
        ),
      );
    }

    return StepFrame(
      action: FilledButton(
        onPressed: _complete ? () => widget.done(StepOutcome(correct: _mistakes == 0)) : null,
        child: Text(_complete ? 'Devam' : 'Eşleştir (${_matched.length}/${s.pairs.length})'),
      ),
      children: [
        Text(s.promptTr ?? 'Eşleştir', style: context.text.titleLarge),
        const SizedBox(height: 4),
        Text('Önce Almanca kelimeye, sonra anlamına dokun.', style: context.text.bodySmall),
        const SizedBox(height: 16),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final i in _left)
                tile(s.pairs[i].de,
                    german: true,
                    done: _matched.contains(i),
                    selected: _pickLeft == i,
                    wrong: _wrong?.$1 == i,
                    onTap: () => setState(() {
                          _pickLeft = i;
                          _tryPair();
                        })),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final i in _right)
                tile(s.pairs[i].tr,
                    done: _matched.contains(i),
                    selected: _pickRight == i,
                    wrong: _wrong?.$2 == i,
                    onTap: () => setState(() {
                          _pickRight = i;
                          _tryPair();
                        })),
            ]),
          ),
        ]),
        if (_complete) ...[
          const SizedBox(height: 8),
          FeedbackPanel(
            positive: _mistakes == 0,
            title: _mistakes == 0 ? 'Hepsi ilk seferde doğru!' : 'Tamamlandı',
            body: _mistakes == 0 ? null : '$_mistakes yanlış eşleştirme oldu. Bu kelimeler bir sonraki turda yine karşına çıkabilir.',
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------ tip

class TipStepView extends StatelessWidget {
  const TipStepView({super.key, required this.step, required this.done});
  final TipStep step;
  final StepDone done;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = step;
    return StepFrame(
      action: FilledButton(onPressed: () => done(null), child: const Text('Anladım, devam')),
      children: [
        Row(children: [
          Icon(Icons.translate_rounded, color: p.accent),
          const SizedBox(width: 8),
          Expanded(child: Text(s.titleTr, style: context.text.headlineSmall)),
        ]),
        const SizedBox(height: 10),
        Text(s.bodyTr, style: context.text.bodyLarge),
        if (s.wrong != null || s.right != null) ...[
          const SizedBox(height: 14),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (s.wrong != null)
                Row(children: [
                  Icon(Icons.close_rounded, color: p.danger, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.wrong!, style: context.reading.copyWith(fontSize: 17, decoration: TextDecoration.lineThrough, color: p.inkMuted))),
                ]),
              if (s.right != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.check_rounded, color: p.success, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(s.right!, style: context.reading.copyWith(fontSize: 17))),
                  SpeakButton(s.right!, size: 20),
                ]),
              ],
            ]),
          ),
        ],
        if (s.examples.isNotEmpty) ...[
          const SizedBox(height: 14),
          for (final e in s.examples)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(e.de, style: context.reading.copyWith(fontSize: 17)),
                    Text(e.tr, style: context.text.bodySmall),
                  ]),
                ),
                SpeakButton(e.de, size: 20),
              ]),
            ),
        ],
      ],
    );
  }
}
