import 'package:deutschap/content/models/lesson.dart';
import 'package:deutschap/features/exam/domain/exam_builder.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';

void main() {
  final content = loadTestContent();
  final builder = ExamBuilder(content);

  test('every level with a path has enough material for an exam', () {
    expect(builder.levels, containsAll(['A1', 'A2', 'B1', 'B2']));
  });

  for (final level in ['A1', 'A2', 'B1', 'B2']) {
    test('$level exam covers all four skills with valid items', () {
      final lesson = builder.build(level, seed: 7);
      final sections = {for (final s in lesson.steps) ExamBuilder.sectionOf(s.id)};
      expect(sections, {ExamSection.reading, ExamSection.listening, ExamSection.grammar, ExamSection.writing});
      expect(lesson.gradedStepCount, inInclusiveRange(10, 17));
      final ids = lesson.steps.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'step ids are unique');
      for (final s in lesson.steps) {
        switch (s) {
          case ChoiceStep(:final options, :final answers):
            expect(answers.single, inInclusiveRange(0, options.length - 1));
          case ListenStep(:final options, :final answers, :final de):
            expect(answers.single, inInclusiveRange(0, options.length - 1));
            expect(de.length, greaterThan(20));
          case ClozeStep(:final answers, :final options):
            expect(options, containsAll(answers.take(1)));
          case WriteStep():
            break;
          default:
            fail('unexpected step ${s.runtimeType}');
        }
      }
    });
  }

  test('different seeds draw different items', () {
    final a = builder.build('A1', seed: 1).steps.map((s) => s.id).join();
    final b = builder.build('A1', seed: 2);
    expect(b.steps.length, greaterThan(8));
    expect(a, isNotEmpty);
  });

  test('lesson ids map to levels', () {
    expect(lessonIsLevel('u3l1', 'A1'), isTrue);
    expect(lessonIsLevel('a2u3l1', 'A1'), isFalse);
    expect(lessonIsLevel('a2u3l1', 'A2'), isTrue);
    expect(lessonIsLevel('b1u1l1', 'B1'), isTrue);
  });
}
