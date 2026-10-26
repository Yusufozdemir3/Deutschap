import 'package:deutschap/content/models/lesson.dart';
import 'package:deutschap/features/conversation/domain/language_issue.dart';
import 'package:deutschap/features/home/domain/recommender.dart';
import 'package:deutschap/features/mistakes/domain/mistake_book.dart';
import 'package:deutschap/features/progress/data/progress_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';

void main() {
  final content = loadTestContent();
  final book = MistakeBook(content);
  final t0 = DateTime(2026, 3, 1, 9);
  AttemptRecord a(String type, String item, bool ok, int minute) =>
      AttemptRecord(activityType: type, activityId: 'x', itemId: item, correct: ok, at: t0.add(Duration(minutes: minute)));

  final clozeId = content.lesson('u4l1')!.steps.firstWhere((s) => s is ClozeStep).id;

  test('a wrong answer is open until the same item is answered correctly', () {
    final open = book.open([a('lesson', clozeId, false, 1), a('lesson', clozeId, false, 2)], const []);
    expect(open.single.source, MistakeSource.lesson);
    expect(open.single.misses, 2);
    expect(open.single.step!.id, MistakeBook.reviewStepId('lesson', clozeId));
    expect(book.open([a('lesson', clozeId, false, 1), a('lesson', clozeId, true, 5)], const []), isEmpty);
  });

  test('drill and listening mistakes are rebuilt as steps', () {
    final open = book.open([
      a('drill', 'termin:article', false, 1),
      a('listening', 'l_bahnhof#q0', false, 2),
      a('drill', 'kaffee:match', false, 3),
    ], const []);
    expect(open.map((m) => m.source).toSet(), {MistakeSource.drill, MistakeSource.listening});
    expect(open.firstWhere((m) => m.source == MistakeSource.drill).step, isA<ArticleStep>());
    expect(open.firstWhere((m) => m.source == MistakeSource.listening).step, isA<ListenStep>());
  });

  test('conversation corrections become "which is right" items and close when fixed', () {
    const issue = LanguageIssue(
      kind: IssueKind.grammar,
      severity: IssueSeverity.error,
      original: 'Ich habe nach Hause gegangen.',
      corrected: 'Ich bin nach Hause gegangen.',
      explanationTr: 'gehen → sein',
      ruleId: 'perfekt_sein',
    );
    final conv = ConversationRecord(id: 'c1', scenarioId: 'cafe', mode: 'guided', status: 'completed', goalsDone: const [], corrections: const [issue], updatedAt: t0);
    final open = book.open(const [], [conv]);
    final step = open.single.step as ChoiceStep;
    expect(step.options[step.answers.single], issue.corrected);
    final key = MistakeBook.conversationKey(issue);
    expect(book.open([a(MistakeBook.conversationFix, key, true, 10)], [conv]), isEmpty);
  });

  test('review step ids round-trip and the review skips writing tasks', () {
    expect(MistakeBook.parseReviewStepId('mistake:drill:termin:article'), ('drill', 'termin:article'));
    expect(MistakeBook.parseReviewStepId('u1l1#2'), isNull);
    final write = content.lessons.expand((l) => l.steps).firstWhere((s) => s is WriteStep);
    final open = book.open([a('lesson', write.id, false, 1), a('lesson', clozeId, false, 2)], const []);
    expect(book.review(open).steps.length, 1);
  });

  test('many open mistakes lead to a weekly review recommendation', () {
    final recs = const Recommender().recommend(const LearnerSnapshot(openMistakes: 6));
    expect(recs.map((r) => r.route), contains('/mistakes/review'));
    expect(const Recommender().recommend(const LearnerSnapshot(openMistakes: 6, mistakesReviewedThisWeek: true)).map((r) => r.route), isNot(contains('/mistakes/review')));
  });
}
