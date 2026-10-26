import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/clock.dart';
import '../../../ui/widgets.dart';
import '../../home/domain/recommender.dart';
import '../domain/article_rules.dart';

/// Guess the article from the ending, then see the rule (and its
/// exceptions). Teaches patterns instead of isolated guesses.
class ArticleGameScreen extends ConsumerStatefulWidget {
  const ArticleGameScreen({super.key});
  @override
  ConsumerState<ArticleGameScreen> createState() => _ArticleGameScreenState();
}

class _ArticleGameScreenState extends ConsumerState<ArticleGameScreen> {
  List<ArticleQuestion>? _round;
  int _i = 0;
  String? _picked;
  int _right = 0;

  void _start() {
    final now = ref.read(clockProvider)();
    setState(() {
      _round = articleRound(ref.read(contentProvider).lexicon, seed: now.millisecondsSinceEpoch);
      _i = 0;
      _picked = null;
      _right = 0;
    });
  }

  Future<void> _answer(String article) async {
    final q = _round![_i];
    final ok = article == q.lexeme.article;
    setState(() {
      _picked = article;
      if (ok) _right++;
    });
    unawaited(ref.read(speechServiceProvider).speak(q.lexeme.headword));
    await ref.read(progressRepositoryProvider).recordAttempt(activityType: 'article_game', activityId: 'article_game', itemId: q.lexeme.id, correct: ok, assisted: false);
  }

  Future<void> _next() async {
    if (_i + 1 >= _round!.length) {
      await ref.read(progressRepositoryProvider).logActivity(ActivityKind.practice, refId: 'article_game', summary: '$_right/${_round!.length}');
      ref.bumpData();
    }
    setState(() {
      _i++;
      _picked = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final round = _round;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Artikel ipuçları')),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: round == null ? _intro(context) : (_i >= round.length ? _result(context, round) : _question(context, round)),
          ),
        ],
      ),
    );
  }

  Widget _intro(BuildContext context) {
    final p = context.palette;
    Widget group(String article, String title) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SectionTitle(title),
          for (final r in articleRules.where((r) => r.article == article))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AppCard(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text('-${r.suffix} → ${r.article}', style: context.text.titleSmall!.copyWith(fontFamily: context.serif))),
                    Pill(r.strength.labelTr, color: r.strength == RuleStrength.always ? p.successSoft : null),
                  ]),
                  Text(r.noteTr, style: context.text.bodySmall),
                  if (r.examples.isNotEmpty) Text(r.examples.join(' · '), style: context.reading.copyWith(fontSize: 15)),
                ]),
              ),
            ),
        ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Almancada artikel çoğu zaman ezberlenir, ama bazı ekler güvenilir ipucu verir. Bileşik isimlerde artikel son parçadan gelir: '
          'die Nummer → die Telefonnummer.', style: context.text.bodyMedium),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: _start, icon: const Icon(Icons.play_arrow_rounded), label: const Text('Oyuna başla (10 isim)')),
      group('die', 'die – dişil'),
      group('das', 'das – nötr'),
      group('der', 'der – eril'),
    ]);
  }

  Widget _question(BuildContext context, List<ArticleQuestion> round) {
    final q = round[_i];
    final p = context.palette;
    final answered = _picked != null;
    final ok = _picked == q.lexeme.article;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LinearProgressIndicator(value: (_i + (answered ? 1 : 0)) / round.length),
      const SizedBox(height: 24),
      Text('Sonuna bak: hangi artikel?', style: context.text.titleMedium, textAlign: TextAlign.center),
      const SizedBox(height: 4),
      Text(q.lexeme.tr, style: context.text.bodyMedium!.copyWith(color: p.inkMuted), textAlign: TextAlign.center),
      const SizedBox(height: 20),
      Center(
        child: Text.rich(
          TextSpan(children: [
            if (answered) TextSpan(text: '${q.lexeme.article} '),
            TextSpan(text: q.lexeme.lemma.substring(0, q.lexeme.lemma.length - q.rule.suffix.length)),
            TextSpan(text: q.lexeme.lemma.substring(q.lexeme.lemma.length - q.rule.suffix.length), style: TextStyle(color: p.accent, fontWeight: FontWeight.w700)),
          ]),
          style: context.text.displaySmall!.copyWith(fontFamily: context.serif),
        ),
      ),
      const SizedBox(height: 24),
      Row(children: [
        for (final a in const ['der', 'die', 'das'])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AppCard(
                onTap: answered ? null : () => _answer(a),
                color: !answered ? null : (a == q.lexeme.article ? p.successSoft : (a == _picked ? p.dangerSoft : null)),
                padding: const EdgeInsets.symmetric(vertical: 16),
                semanticLabel: a,
                child: Text(a, textAlign: TextAlign.center, style: context.text.titleLarge),
              ),
            ),
          ),
      ]),
      if (answered) ...[
        const SizedBox(height: 16),
        FeedbackPanel(
          positive: ok,
          title: ok ? 'Doğru: ${q.lexeme.headword}' : 'Doğrusu: ${q.lexeme.headword}',
          body: q.isException
              ? 'Kural: ${q.rule.titleTr}. Bu kelime bir istisna! ${q.rule.noteTr}'
              : 'Kural: ${q.rule.titleTr}. ${q.rule.noteTr}',
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _next, child: Text(_i + 1 >= round.length ? 'Sonucu gör' : 'Sıradaki')),
      ],
    ]);
  }

  Widget _result(BuildContext context, List<ArticleQuestion> round) {
    final exceptions = round.where((q) => q.isException).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 16),
      Text('${round.length} isimden $_right tanesini bildin', style: context.text.headlineSmall, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text('Ekler güçlü bir ipucu ama her zaman kesin değil. Şüphedeysen sözlüğe bak ve kelimeyi artikeliyle kaydet.', style: context.text.bodyMedium, textAlign: TextAlign.center),
      if (exceptions.isNotEmpty) ...[
        const SectionTitle('Bu turdaki istisnalar'),
        for (final q in exceptions) Text('• ${q.lexeme.headword} (kural: ${q.rule.titleTr})', style: context.text.bodyMedium),
      ],
      const SizedBox(height: 20),
      FilledButton.icon(onPressed: _start, icon: const Icon(Icons.refresh_rounded), label: const Text('Yeni tur')),
      const SizedBox(height: 8),
      OutlinedButton(onPressed: () => setState(() => _round = null), child: const Text('Kurallara dön')),
    ]);
  }
}
