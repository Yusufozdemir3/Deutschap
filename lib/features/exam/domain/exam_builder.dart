import 'dart:math';

import '../../../content/content_bundle.dart';
import '../../../content/models/lesson.dart';

/// Skills a mini exam covers, in the order they are asked.
enum ExamSection {
  reading('Okuma'),
  listening('Dinleme'),
  grammar('Dil bilgisi'),
  writing('Yazma');

  const ExamSection(this.labelTr);
  final String labelTr;
}

/// Lesson ids belong to a level by their prefix: u1l1 → A1, a2u1l1 → A2.
bool lessonIsLevel(String lessonId, String level) => switch (level) {
      'A1' => RegExp(r'^u\d').hasMatch(lessonId),
      'A2' => lessonId.startsWith('a2'),
      'B1' => lessonId.startsWith('b1'),
      _ => false,
    };

/// Builds a short mixed practice test from content that already exists:
/// reading and listening questions, grammar items from the level's lessons
/// and one short writing task. Nothing here is invented, so every answer
/// key was checked by the content tests.
class ExamBuilder {
  ExamBuilder(this.content);
  final ContentBundle content;

  /// Levels with enough material for an exam.
  List<String> get levels => [
        for (final p in content.paths)
          if (p.units.isNotEmpty && p.units.expand((u) => u.lessons).length >= 4) p.level,
      ];

  /// Section of a step id produced by [build] (`exam:<section>#n`), if any.
  static ExamSection? sectionOf(String stepId) {
    final m = RegExp(r'^exam:(\w+)#').firstMatch(stepId);
    return m == null ? null : ExamSection.values.where((s) => s.name == m.group(1)).firstOrNull;
  }

  Lesson build(String level, {int seed = 0}) {
    final rnd = Random(seed);
    final steps = <LessonStep>[];

    // Reading: up to four questions from two texts of the level.
    final texts = content.readings.where((r) => r.level == level).toList()..shuffle(rnd);
    var n = 0;
    for (final r in texts.take(2)) {
      for (final q in r.questions.take(2)) {
        steps.add(ChoiceStep(
          'exam:reading#${n++}',
          promptTr: '"${r.title}" metnine göre: ${q.questionTr}',
          de: r.body,
          options: q.options,
          answers: [q.answer],
          explainTr: q.explainTr,
        ));
      }
    }

    // Listening: up to four questions from two tracks of the level.
    final tracks = content.listening.where((t) => t.level == level).toList()..shuffle(rnd);
    n = 0;
    for (final t in tracks.take(2)) {
      final spoken = t.lines.map((l) => l.de).join(' ');
      for (final q in t.questions.take(2)) {
        steps.add(ListenStep(
          'exam:listening#${n++}',
          de: spoken,
          promptTr: q.questionTr,
          options: q.options,
          answers: [q.answer],
          explainTr: q.explainTr,
        ));
      }
    }

    // Grammar: eight gap or choice items from the level's lessons.
    final pool = <LessonStep>[
      for (final l in content.orderedLessons)
        if (lessonIsLevel(l.id, level))
          for (final s in l.steps)
            if ((s is ClozeStep && s.options.isNotEmpty) || (s is ChoiceStep && s.de != null && s.de!.contains('___'))) s,
    ]..shuffle(rnd);
    n = 0;
    for (final s in pool.take(8)) {
      steps.add(switch (s) {
        ClozeStep() => ClozeStep('exam:grammar#${n++}', de: s.de, tr: s.tr, answers: s.answers, options: s.options, explainTr: s.explainTr),
        ChoiceStep() => ChoiceStep('exam:grammar#${n++}', promptTr: s.promptTr, de: s.de, options: s.options, answers: s.answers, explainTr: s.explainTr),
        _ => s,
      });
    }

    // Writing: one task.
    final writes = <WriteStep>[
      for (final l in content.orderedLessons)
        if (lessonIsLevel(l.id, level))
          for (final s in l.steps)
            if (s is WriteStep) s,
    ]..shuffle(rnd);
    if (writes.isNotEmpty) {
      final w = writes.first;
      steps.add(WriteStep('exam:writing#0', promptTr: w.promptTr, requirements: w.requirements, model: w.model, minWords: w.minWords));
    }

    return Lesson(
      id: 'exam_$level',
      titleTr: 'Mini sınav · $level',
      objectiveTr: 'Okuma, dinleme, dil bilgisi ve yazma: gerçek bir sınavın kısa bir provası.',
      minutes: 15,
      steps: steps,
    );
  }
}
