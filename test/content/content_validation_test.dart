import 'package:deutschap/content/content_validator.dart';
import 'package:deutschap/content/models/story.dart';
import 'package:deutschap/features/conversation/domain/conversation_engine.dart';
import 'package:deutschap/features/conversation/domain/error_detectors.dart';
import 'package:deutschap/learning/text/tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';

void main() {
  final content = loadTestContent();

  test('all shipped content passes the validator', () {
    final problems = ContentValidator(content, loadContentSources()).validate();
    expect(problems, isEmpty, reason: problems.join('\n'));
  });

  test('content is not trivially small', () {
    expect(content.lexicon.length, greaterThan(200));
    expect(content.orderedLessons.length, greaterThanOrEqualTo(12));
    expect(content.episodes.length, greaterThanOrEqualTo(4));
    expect(content.scenarios.length, greaterThanOrEqualTo(5));
  });

  group('recap vocabulary actually occurs in its episode', () {
    for (final e in content.episodes) {
      test(e.id, () {
        final sentences = <String>[
          for (final n in e.nodes.values)
            ...switch (n) {
              NarrationNode(:final de) || LineNode(:final de) => [de],
              ChoiceNode(:final choices) => [for (final c in choices) c.de],
              _ => const <String>[],
            },
        ];
        final missing = <String>[];
        for (final id in e.vocab) {
          final found = sentences.any((s) {
            final ws = words(s);
            for (var i = 0; i < ws.length; i++) {
              if (content.lexicon.lookupWord(ws[i], sentenceWords: ws.map((w) => w.toLowerCase()).toList(), wordIndex: i).lexemes.any((l) => l.id == id)) {
                return true;
              }
              if (content.lexicon.phrasesAt(ws, i).any((p) => p.lexeme.id == id)) return true;
            }
            return false;
          });
          if (!found) missing.add(id);
        }
        expect(missing, isEmpty, reason: 'not found in the text of ${e.id}');
      });
    }
  });

  group('scenario hints complete their scenario', () {
    for (final s in content.scenarios) {
      test(s.id, () async {
        final engine = OfflineScenarioEngine(ErrorDetectors(content.lexicon));
        var state = engine.start(s, ConversationMode.guided);
        for (final g in s.goals) {
          // The first hint is the model phrase offered in guided mode; a
          // name placeholder is filled in like a learner would.
          state = await engine.respond(state, g.hints.first.de.replaceAll('…', 'Deniz'));
          expect(state.goalsDone, contains(g.id), reason: 'hint "${g.hints.first.de}" did not reach ${g.id}');
        }
        expect(state.isComplete, isTrue);
      });
    }
  });
}
