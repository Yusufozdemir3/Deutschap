import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/lesson.dart';
import '../../../content/models/scenario.dart';
import '../../../ui/widgets.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/data/progress_repository.dart';
import '../../vocabulary/domain/vocab_entry.dart';
import 'step_views.dart';

class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({super.key, required this.lessonId});
  final String lessonId;
  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  Lesson? _lesson;
  final _queue = <int>[];
  int _pos = 0;

  /// Steps in the main pass; positions after it are retries of missed items.
  int _mainCount = 0;
  int _firstTryCorrect = 0;
  final _graded = <int>{};
  final _retried = <int>{};
  bool _loading = true;
  bool _resumed = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final lesson = ref.read(contentProvider).lesson(widget.lessonId);
    if (lesson == null) {
      setState(() => _loading = false);
      return;
    }
    final saved = await ref.read(progressRepositoryProvider).lesson(lesson.id);
    var start = 0;
    if (saved != null && saved.status == LessonStatus.inProgress && saved.stepIndex > 0 && saved.stepIndex < lesson.steps.length) {
      start = saved.stepIndex;
      _firstTryCorrect = saved.correct;
      _resumed = true;
      for (var i = 0; i < start; i++) {
        if (lesson.steps[i].isGraded) _graded.add(i);
      }
    }
    if (!mounted) return;
    setState(() {
      _lesson = lesson;
      _queue.addAll([for (var i = start; i < lesson.steps.length; i++) i]);
      _mainCount = _queue.length;
      _loading = false;
    });
  }

  void _restart() {
    setState(() {
      _queue
        ..clear()
        ..addAll(List.generate(_lesson!.steps.length, (i) => i));
      _mainCount = _queue.length;
      _pos = 0;
      _firstTryCorrect = 0;
      _graded.clear();
      _retried.clear();
      _resumed = false;
    });
  }

  Future<void> _onDone(StepOutcome? outcome) async {
    final lesson = _lesson!;
    final index = _queue[_pos];
    final step = lesson.steps[index];
    final repo = ref.read(progressRepositoryProvider);
    if (outcome != null) {
      await repo.recordAttempt(activityType: 'lesson', activityId: lesson.id, itemId: step.id, correct: outcome.correct, assisted: outcome.assisted);
      if (!_graded.contains(index)) {
        _graded.add(index);
        if (outcome.correct && !outcome.assisted) _firstTryCorrect++;
        // A missed item comes back once at the end of the lesson.
        if (!outcome.correct && _retried.add(index)) _queue.add(index);
      }
    }
    final nextPos = _pos + 1;
    if (nextPos >= _queue.length) {
      await repo.completeLesson(lesson.id, correct: _firstTryCorrect, total: lesson.gradedStepCount);
      ref.bumpData();
      if (mounted) setState(() => _finished = true);
      return;
    }
    final nextIndex = _queue[nextPos];
    if (nextIndex > index) {
      await repo.saveLessonStep(lesson.id, stepIndex: nextIndex, correct: _firstTryCorrect, total: lesson.gradedStepCount);
    }
    if (mounted) setState(() => _pos = nextPos);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    final lesson = _lesson;
    if (lesson == null) return Scaffold(appBar: AppBar(leading: const BackOrHomeButton()), body: const ErrorState(message: 'Bu ders bulunamadı.'));
    if (_finished) {
      return _LessonComplete(
        lesson: lesson,
        firstTry: _firstTryCorrect,
        onRestart: () => setState(() {
          _finished = false;
          _restart();
        }),
      );
    }

    final index = _queue[_pos];
    final step = lesson.steps[index];
    final retrying = _pos >= _mainCount;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Kapat (ilerleme kaydedildi)', onPressed: () => closeOrHome(context)),
        title: Semantics(
          label: 'İlerleme ${_pos + 1} / ${_queue.length}',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(value: (_pos + 1) / _queue.length, minHeight: 8),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_resumed && _pos == 0)
            MaterialBanner(
              content: const Text('Kaldığın yerden devam ediyorsun.'),
              actions: [TextButton(onPressed: _restart, child: const Text('Baştan başla'))],
            ),
          if (retrying)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Pill('Tekrar deneyelim', icon: Icons.replay_rounded, color: context.palette.accentSoft, textColor: context.palette.accent),
            ),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey('${step.id}#$_pos'),
              child: switch (step) {
                IntroStep() => IntroStepView(step: step, lesson: lesson, done: _onDone),
                GrammarStep() => GrammarStepView(step: step, done: _onDone),
                DialogueStep() => DialogueStepView(step: step, lesson: lesson, done: _onDone),
                ChoiceStep() => ChoiceStepView(step: step, done: _onDone),
                ArticleStep() => ArticleStepView(step: step, done: _onDone),
                ClozeStep() => ClozeStepView(step: step, done: _onDone),
                OrderStep() => OrderStepView(step: step, done: _onDone),
                TranslateStep() => TranslateStepView(step: step, done: _onDone),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonComplete extends ConsumerWidget {
  const _LessonComplete({required this.lesson, required this.firstTry, required this.onRestart});
  final Lesson lesson;
  final int firstTry;
  final VoidCallback onRestart;

  Scenario? _relatedScenario(List<Scenario> all) {
    Scenario? best;
    var bestOverlap = 0;
    for (final s in all) {
      final overlap = s.vocab.where(lesson.vocab.contains).length;
      if (overlap > bestOverlap) {
        best = s;
        bestOverlap = overlap;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(contentProvider);
    final saved = ref.watch(savedLexemeIdsProvider).valueOrNull ?? const {};
    final next = ref.watch(nextLessonProvider);
    final scenario = _relatedScenario(content.scenarios);
    final unsaved = lesson.vocab.where((v) => !saved.contains(v)).toList();
    final total = lesson.gradedStepCount;
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(leading: IconButton(icon: const Icon(Icons.close_rounded), tooltip: 'Kapat', onPressed: () => closeOrHome(context))),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Icon(Icons.check_circle_rounded, size: 56, color: p.success),
              const SizedBox(height: 12),
              Text('Ders tamamlandı', style: context.text.headlineMedium, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(lesson.titleTr, style: context.text.bodyLarge!.copyWith(color: p.inkMuted), textAlign: TextAlign.center),
              const SizedBox(height: 24),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Ne başardın?', style: context.text.titleMedium),
                  const SizedBox(height: 8),
                  Text('• $total alıştırmanın $firstTry tanesini ilk denemede, ipucusuz doğru yaptın.', style: context.text.bodyMedium),
                  Text('• Hedef: ${lesson.objectiveTr}', style: context.text.bodyMedium),
                  const SizedBox(height: 8),
                  Text('Bu kısa süreli bir sonuç. Kalıcılık, birkaç gün sonra yapılan tekrarlarla ölçülür.', style: context.text.bodySmall),
                ]),
              ),
              if (lesson.vocab.isNotEmpty) ...[
                const SectionTitle('Bu dersin kelimeleri'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final id in lesson.vocab)
                    if (content.lexicon.byId(id) case final l?)
                      Chip(
                        avatar: Icon(saved.contains(id) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 16, color: saved.contains(id) ? p.success : p.inkMuted),
                        label: Text(l.headword),
                      ),
                ]),
                if (unsaved.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final repo = ref.read(vocabRepositoryProvider);
                      for (final id in unsaved) {
                        final l = content.lexicon.byId(id)!;
                        await repo.saveLexeme(l,
                            context: SourceContext(
                              type: SourceType.lesson,
                              sourceId: lesson.id,
                              title: lesson.titleTr,
                              sentence: l.examples.isEmpty ? '' : l.examples.first.de,
                              sentenceTr: l.examples.isEmpty ? null : l.examples.first.tr,
                            ));
                      }
                      ref.bumpData();
                      if (context.mounted) showToast(context, '${unsaved.length} kelime tekrar planına eklendi');
                    },
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text('Kalan ${unsaved.length} kelimeyi kaydet'),
                  ),
                ],
              ],
              const SectionTitle('Sırada ne var? (isteğe bağlı)'),
              if (scenario != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppCard(
                    onTap: () => context.pushReplacement('/scenario/${scenario.id}'),
                    child: Row(children: [
                      Icon(Icons.forum_rounded, color: p.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Konuşmada dene: ${scenario.titleTr}', style: context.text.titleSmall),
                          Text('Bu dersin kelimelerini gerçekçi bir durumda kullan.', style: context.text.bodySmall),
                        ]),
                      ),
                    ]),
                  ),
                ),
              if (next != null && next.id != lesson.id)
                AppCard(
                  onTap: () => context.pushReplacement('/lesson/${next.id}'),
                  child: Row(children: [
                    Icon(Icons.route_rounded, color: p.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Sıradaki ders: ${next.titleTr}', style: context.text.titleSmall),
                        Text('${next.minutes} dk', style: context.text.bodySmall),
                      ]),
                    ),
                  ]),
                ),
              const SizedBox(height: 16),
              FilledButton(onPressed: () => closeOrHome(context), child: const Text('Şimdilik bu kadar')),
              const SizedBox(height: 8),
              TextButton(onPressed: onRestart, child: const Text('Dersi tekrar yap')),
            ]),
          ),
        ],
      ),
    );
  }
}
