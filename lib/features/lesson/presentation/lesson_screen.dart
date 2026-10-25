import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/lesson.dart';
import '../../../content/models/scenario.dart';
import '../../../core/clock.dart';
import '../../../ui/widgets.dart';
import '../../progress/application/progress_providers.dart';
import '../../progress/data/progress_repository.dart';
import '../../vocabulary/domain/vocab_entry.dart';
import '../../home/domain/recommender.dart';
import '../../drill/application/drill_words.dart';
import '../../exam/domain/exam_builder.dart';
import '../../drill/domain/vocab_drill.dart';
import '../../practice/domain/practice_generator.dart';
import 'step_views.dart';

class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen({super.key, required this.lessonId, this.practice, this.drill, this.examLevel});
  final String lessonId;

  /// A generated vocabulary drill. Like [practice], it records attempts
  /// (per word and exercise type) but not lesson progress.
  final DrillSpec? drill;

  /// A generated mini exam for this level (see [ExamBuilder]). Items are not
  /// repeated at the end and results are recorded as `exam` attempts.
  final String? examLevel;

  /// Generated, focused practice instead of a curriculum lesson. It
  /// records attempts but does not touch lesson progress.
  final PracticeTopic? practice;
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

  /// Mini exam only: first-try results per skill.
  final _sections = <ExamSection, (int right, int total)>{};
  bool _loading = true;
  bool _resumed = false;
  bool _finished = false;

  bool get _generated => widget.practice != null || widget.drill != null || widget.examLevel != null;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final now = ref.read(clockProvider)();
    final content = ref.read(contentProvider);
    final Lesson? lesson;
    if (widget.examLevel case final level?) {
      final built = ExamBuilder(content).build(level, seed: now.millisecondsSinceEpoch);
      lesson = built.steps.where((s) => s.isGraded).length >= 4 ? built : null;
    } else if (widget.drill case final spec?) {
      final seed = now.millisecondsSinceEpoch;
      final words = await resolveDrillWords(spec,
          content: content, vocab: ref.read(vocabRepositoryProvider), progress: ref.read(progressRepositoryProvider), seed: seed);
      final built = VocabDrillGenerator(content.lexicon).build(words, mode: spec.mode, size: spec.size, seed: seed);
      lesson = built.steps.where((s) => s.isGraded).isEmpty ? null : built;
    } else if (widget.practice != null) {
      lesson = PracticeGenerator(content.lexicon).build(widget.practice!, seed: now.year * 1000 + now.month * 50 + now.day);
    } else {
      lesson = content.lesson(widget.lessonId);
    }
    if (lesson == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final saved = _generated ? null : await ref.read(progressRepositoryProvider).lesson(lesson.id);
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
    final steps = lesson.steps.length;
    setState(() {
      _lesson = lesson;
      _queue.addAll([for (var i = start; i < steps; i++) i]);
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
      final drillItem = widget.drill == null ? null : VocabDrillGenerator.describe(step, lesson);
      await repo.recordAttempt(
        activityType: widget.examLevel != null ? 'exam' : (widget.drill != null ? 'drill' : (widget.practice != null ? 'practice' : 'lesson')),
        activityId: lesson.id,
        itemId: drillItem == null ? step.id : drillItemId(drillItem.$1, drillItem.$2),
        correct: outcome.correct,
        assisted: outcome.assisted,
      );
      if (!_graded.contains(index)) {
        _graded.add(index);
        if (outcome.correct && !outcome.assisted) _firstTryCorrect++;
        if (widget.examLevel != null) {
          final section = ExamBuilder.sectionOf(step.id);
          if (section != null) {
            final prev = _sections[section] ?? (0, 0);
            _sections[section] = (prev.$1 + (outcome.correct && !outcome.assisted ? 1 : 0), prev.$2 + 1);
          }
        }
        // A missed item comes back once at the end of the lesson.
        if (!outcome.correct && widget.examLevel == null && _retried.add(index)) _queue.add(index);
      }
    }
    final nextPos = _pos + 1;
    if (nextPos >= _queue.length) {
      if (widget.examLevel != null) {
        await repo.logActivity(ActivityKind.practice, refId: 'exam_${widget.examLevel}', summary: '$_firstTryCorrect/${lesson.gradedStepCount}');
      } else if (widget.drill != null) {
        await repo.logActivity(ActivityKind.practice, refId: 'drill', summary: '$_firstTryCorrect/${lesson.gradedStepCount}');
      } else if (widget.practice != null) {
        await repo.logActivity(ActivityKind.practice, refId: widget.practice!.name, summary: '$_firstTryCorrect/${lesson.gradedStepCount}');
      } else {
        await repo.completeLesson(lesson.id, correct: _firstTryCorrect, total: lesson.gradedStepCount);
      }
      ref.bumpData();
      if (mounted) setState(() => _finished = true);
      return;
    }
    final nextIndex = _queue[nextPos];
    if (nextIndex > index && !_generated) {
      await repo.saveLessonStep(lesson.id, stepIndex: nextIndex, correct: _firstTryCorrect, total: lesson.gradedStepCount);
    }
    if (mounted) setState(() => _pos = nextPos);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    final lesson = _lesson;
    if (lesson == null) {
      return Scaffold(
        appBar: AppBar(leading: const BackOrHomeButton()),
        body: widget.drill != null
            ? EmptyState(
                icon: Icons.style_outlined,
                title: 'Bu seçim için kelime yok',
                message: widget.drill!.source == 'weak'
                    ? 'Henüz zorlandığın bir kelime yok. Birkaç antrenman yaptıktan sonra burada yanlış yaptığın kelimeler toplanır.'
                    : 'Başka bir kaynak ya da alıştırma türü seç. Kaydettiğin kelimelerle çalışmak için önce kelime kaydet.',
              )
            : const ErrorState(message: 'Bu ders bulunamadı.'),
      );
    }
    if (_finished) {
      return _LessonComplete(
        lesson: lesson,
        firstTry: _firstTryCorrect,
        drill: widget.drill,
        exam: widget.examLevel != null,
        sections: _sections,
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
                ListenStep() => ListenStepView(step: step, done: _onDone),
                WriteStep() => WriteStepView(step: step, done: _onDone),
                MatchStep() => MatchStepView(step: step, done: _onDone),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LessonComplete extends ConsumerWidget {
  const _LessonComplete({required this.lesson, required this.firstTry, required this.onRestart, this.drill, this.exam = false, this.sections = const {}});
  final Lesson lesson;
  final DrillSpec? drill;
  final bool exam;
  final Map<ExamSection, (int right, int total)> sections;
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
              Text(exam ? 'Sınav bitti' : (drill != null ? 'Antrenman bitti' : 'Ders tamamlandı'), style: context.text.headlineMedium, textAlign: TextAlign.center),
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
                  if (exam)
                    for (final e in sections.entries)
                      Text('• ${e.key.labelTr}: ${e.value.$2} sorudan ${e.value.$1}', style: context.text.bodyMedium),
                  Text(
                      exam
                          ? 'Bu sadece kısa bir prova; gerçek sınavın yerini tutmaz. Zayıf çıkan bölümü o becerinin sekmesinde çalışabilirsin.'
                          : 'Bu kısa süreli bir sonuç. Kalıcılık, birkaç gün sonra yapılan tekrarlarla ölçülür.',
                      style: context.text.bodySmall),
                ]),
              ),
              if (lesson.vocab.isNotEmpty) ...[
                SectionTitle(drill != null ? 'Çalıştığın kelimeler' : 'Bu dersin kelimeleri'),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final id in lesson.vocab)
                    if (content.lexicon.byId(id) case final l?)
                      Tag(l.headword, icon: saved.contains(id) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, selected: saved.contains(id)),
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
              if (drill != null) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => context.pushReplacement('/drill/run?${drill!.query}'),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Yeni tur'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => context.pushReplacement('/drill'), child: const Text('Başka bir antrenman seç')),
              ],
              if (drill == null && !exam) const SectionTitle('Sırada ne var? (isteğe bağlı)'),
              if (scenario != null && drill == null && !exam)
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
              if (next != null && next.id != lesson.id && drill == null && !exam)
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
              if (drill == null && !exam) TextButton(onPressed: onRestart, child: const Text('Dersi tekrar yap')),
            ]),
          ),
        ],
      ),
    );
  }
}
