import 'package:deutschap/content/models/scenario.dart';
import 'package:deutschap/content/models/story.dart';
import 'package:deutschap/features/conversation/domain/conversation_engine.dart';
import 'package:deutschap/features/conversation/domain/error_detectors.dart';
import 'package:deutschap/features/conversation/domain/language_issue.dart';
import 'package:deutschap/features/home/domain/recommender.dart';
import 'package:deutschap/features/stories/domain/story_runner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';

void main() {
  final content = loadTestContent();
  final detectors = ErrorDetectors(content.lexicon);

  group('StoryRunner', () {
    final episode = content.episode('nib_e1_a1')!;
    final runner = StoryRunner(episode);

    StoryState advanceToChoice(StoryState s) {
      while (runner.node(s.nodeId) is! ChoiceNode && !runner.isAtEnd(s)) {
        s = runner.advance(s);
      }
      return s;
    }

    test('wrong choices keep the learner at the node and are remembered', () {
      var s = advanceToChoice(runner.start());
      final r = runner.choose(s, 'c'); // "Ich heißt …"
      expect(r.advanced, isFalse);
      expect(r.state.nodeId, s.nodeId);
      s = runner.choose(r.state, 'a').state;
      expect(s.history.last.wrongChoiceIds, ['c']);
    });

    test('flags route through branch nodes', () {
      final s = advanceToChoice(runner.start());
      final formal = runner.choose(s, 'b').state;
      expect(formal.flags, contains('formell'));
      expect(formal.nodeId, 'n5');
      final casual = runner.choose(s, 'a').state;
      expect(casual.nodeId, 'n6');
    });

    test('every episode can be played to the end with best choices', () {
      for (final e in content.episodes) {
        final r = StoryRunner(e);
        var s = r.start();
        var steps = 0;
        while (!r.isAtEnd(s)) {
          final n = r.node(s.nodeId);
          s = n is ChoiceNode
              ? r.choose(s, n.choices.firstWhere((c) => c.verdict == ChoiceVerdict.best).id).state
              : r.advance(s);
          expect(++steps, lessThan(200), reason: 'loop in ${e.id}');
        }
        final acc = r.choiceAccuracy(s.history);
        expect(acc.firstTry, acc.total);
      }
    });

    test('history round-trips through JSON', () {
      final step = StoryStep('n4', choiceId: 'a', wrongChoiceIds: const ['c']);
      final back = StoryStep.fromJson(step.toJson().cast<String, dynamic>());
      expect(back.nodeId, 'n4');
      expect(back.choiceId, 'a');
      expect(back.wrongChoiceIds, ['c']);
    });
  });

  group('ErrorDetectors', () {
    LanguageIssue? first(String s, {bool formal = false, bool service = false}) {
      final issues = detectors.check(s, formalContext: formal, serviceContext: service);
      return issues.isEmpty ? null : issues.first;
    }

    test('Perfekt with sein (the spec example)', () {
      final i = first('Ich habe gestern ins Kino gegangen.')!;
      expect(i.ruleId, 'perfekt_sein');
      expect(i.corrected, 'Ich bin gestern ins Kino gegangen.');
      expect(i.severity, IssueSeverity.error);
    });

    test('Perfekt with haben is left alone when correct', () {
      expect(first('Ich habe zwei Brötchen gekauft.'), isNull);
      expect(first('Ich habe das Auto gefahren.'), isNull, reason: 'transitive fahren takes haben');
    });

    test('accusative masculine after möchte/hätte gern', () {
      expect(first('Ich möchte ein Kaffee, bitte.')!.corrected, 'Ich möchte einen Kaffee, bitte.');
      expect(first('Ich hätte gern der Tee.')!.corrected, 'Ich hätte gern den Tee.');
    });

    test('feminine and neuter nouns do not get einen', () {
      expect(first('Ich nehme einen Brezel.')!.corrected, 'Ich nehme eine Brezel.');
      expect(first('Ich nehme ein Wasser und eine Brezel.'), isNull);
    });

    test('plural die is not mistaken for a wrong article', () {
      expect(first('Ich nehme die Brötchen.'), isNull);
    });

    test('verb-second after a fronted time word', () {
      final i = first('Heute ich gehe ins Café.')!;
      expect(i.kind, IssueKind.wordOrder);
      expect(i.corrected, 'Heute gehe ich ins Café.');
      expect(first('Heute gehe ich ins Café.'), isNull);
    });

    test('register and politeness are suggestions, not errors', () {
      final reg = first('Kannst du mir helfen?', formal: true)!;
      expect(reg.kind, IssueKind.register);
      expect(reg.severity, IssueSeverity.suggestion);
      final pol = first('Ich will zwei Brötchen.', service: true)!;
      expect(pol.ruleId, 'polite_moechte');
      expect(pol.corrected, 'Ich möchte zwei Brötchen.');
    });

    test('lower-case nouns are flagged, verbs with the same spelling are not', () {
      expect(first('Die rechnung, bitte.')!.ruleId, 'noun_caps');
      expect(first('Wir essen heute zusammen.'), isNull);
    });

    test('correct sentences produce no issues', () {
      for (final s in ['Ich hätte gern einen Cappuccino, bitte.', 'Ich komme aus der Türkei.', 'Am Dienstag habe ich Zeit.']) {
        expect(detectors.check(s), isEmpty, reason: s);
      }
    });
  });

  group('OfflineScenarioEngine', () {
    final engine = OfflineScenarioEngine(detectors);
    final cafe = content.scenario('cafe')!;

    test('understands the meaning despite a grammar error and still reports it', () async {
      var s = engine.start(cafe, ConversationMode.practice);
      s = await engine.respond(s, 'Ich möchte ein Kaffee');
      final learner = s.turns[s.turns.length - 2];
      expect(learner.understood, isTrue);
      expect(learner.goalReached, 'bestellen');
      expect(learner.issues.single.ruleId, startsWith('akkusativ'));
    });

    test('accepts different valid formulations', () async {
      for (final text in ['Einen Cappuccino, bitte.', 'Ich hätte gern einen Latte.', 'Ich nehme einen Espresso.']) {
        final s = await engine.respond(engine.start(cafe, ConversationMode.guided), text);
        expect(s.goalsDone, contains('bestellen'), reason: text);
      }
    });

    test('unknown input gets a fallback and is marked as not understood', () async {
      final s = await engine.respond(engine.start(cafe, ConversationMode.guided), 'Quantenphysik ist toll');
      expect(s.turns[s.turns.length - 2].understood, isFalse);
      expect(s.misunderstandings, 1);
      expect(s.goalsDone, isEmpty);
    });

    test('goals with prerequisites are not skipped', () async {
      final s = await engine.respond(engine.start(cafe, ConversationMode.guided), 'Ich möchte zahlen');
      expect(s.goalsDone, isEmpty);
      expect(s.turns.last.de, contains('bestellen'));
    });

    test('a full conversation completes with a closing line', () async {
      var s = engine.start(cafe, ConversationMode.immersion);
      for (final t in ['Hallo! Einen Tee, bitte.', 'Für hier, bitte.', 'Kann ich mit Karte zahlen?']) {
        s = await engine.respond(s, t);
      }
      expect(s.isComplete, isTrue);
      expect(s.turns.last.de, cafe.closing.de);
      expect(await engine.respond(s, 'Noch etwas'), same(s), reason: 'completed conversations are closed');
    });

    test('negated agreement does not book the appointment', () async {
      final termin = content.scenario('termin')!;
      var s = engine.start(termin, ConversationMode.practice);
      s = await engine.respond(s, 'Ich möchte einen Termin vereinbaren.');
      s = await engine.respond(s, 'Mein Name ist Deniz Aydın.');
      s = await engine.respond(s, 'Dienstag passt mir leider nicht.');
      expect(s.goalsDone, isNot(contains('tag')));
      s = await engine.respond(s, 'Mittwoch passt gut.');
      expect(s.isComplete, isTrue);
    });

    test('scenario patterns compile', () {
      for (final Scenario sc in content.scenarios) {
        for (final i in sc.intents) {
          for (final m in i.matches) {
            expect(() => RegExp(m.pattern), returnsNormally);
          }
        }
      }
    });
  });

  group('Recommender', () {
    const r = Recommender();

    test('due reviews come first and explain why', () {
      final recs = r.recommend(const LearnerSnapshot(dueCards: 12, nextLesson: NamedRef('u1l1', 'Selamlaşma')));
      expect(recs.first.kind, ActivityKind.review);
      expect(recs.first.reasonTr, isNotEmpty);
      expect(recs.map((x) => x.kind), contains(ActivityKind.lesson));
    });

    test('production gap suggests a conversation', () {
      final recs = r.recommend(const LearnerSnapshot(productionGap: 3, practiceScenario: NamedRef('cafe', 'Kafede'), nextLesson: NamedRef('u2l1', 'Sayılar')));
      expect(recs.first.kind, ActivityKind.scenario);
    });

    test('variety: two lessons in a row lowers the next lesson', () {
      final recs = r.recommend(const LearnerSnapshot(
        nextLesson: NamedRef('u2l1', 'Sayılar'),
        nextEpisode: NamedRef('nib_e2_a1', 'Fırında'),
        lastKinds: [ActivityKind.lesson, ActivityKind.lesson],
      ));
      expect(recs.first.kind, ActivityKind.story);
    });

    test('a brand-new learner gets the first lesson', () {
      final recs = r.recommend(const LearnerSnapshot(nextLesson: NamedRef('u1l1', 'Selamlaşma'), nextEpisode: NamedRef('nib_e1_a1', 'Ankunft')));
      expect(recs.first.route, '/lesson/u1l1');
    });
  });
}
