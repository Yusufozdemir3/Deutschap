import 'package:deutschap/content/content_validator.dart';
import 'package:deutschap/content/models/lesson.dart';
import 'package:deutschap/content/models/story.dart';
import 'package:deutschap/features/conversation/domain/conversation_engine.dart';
import 'package:deutschap/features/conversation/domain/error_detectors.dart';
import 'package:deutschap/features/conversation/domain/language_issue.dart';
import 'package:deutschap/features/stories/domain/episode_text.dart';
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

  test('model answers and hint phrases contain no detectable errors', () {
    final detectors = ErrorDetectors(content.lexicon);
    final samples = <String>[
      for (final l in content.lessons)
        for (final s in l.steps)
          if (s is WriteStep) s.model,
      for (final sc in content.scenarios)
        for (final g in sc.goals)
          for (final h in g.hints) h.de.replaceAll('…', 'Deniz'),
    ];
    for (final text in samples) {
      final errors = detectors.check(text).where((i) => i.severity == IssueSeverity.error).toList();
      expect(errors, isEmpty, reason: '"$text" → ${errors.map((e) => e.corrected).join(' | ')}');
    }
  });

  test('no curated German sentence triggers an error detector (false-positive net)', () {
    final detectors = ErrorDetectors(content.lexicon);
    final texts = <String>[
      for (final l in content.lexicon.all) ...l.examples.map((e) => e.de),
      for (final g in content.grammar.values) ...g.examples.map((e) => e.de),
      for (final e in content.episodes) ...episodeLines(e).map((l) => fillName(l.de, 'Deniz')),
      for (final r in content.readings) ...r.paragraphs.map((p) => p.de),
      for (final c in content.discover) c.bodyDe,
      for (final l in content.lessons)
        for (final s in l.steps)
          if (s is DialogueStep) ...s.lines.map((x) => x.de),
    ];
    final flagged = <String>[];
    for (final t in texts) {
      for (final i in detectors.check(t)) {
        if (i.severity == IssueSeverity.error) flagged.add('$t → ${i.corrected}');
      }
    }
    expect(flagged, isEmpty, reason: flagged.join(' | '));
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
      test('${s.id}: every hint reaches its goal', () async {
        final engine = OfflineScenarioEngine(ErrorDetectors(content.lexicon));
        var before = engine.start(s, ConversationMode.guided);
        for (final g in s.goals) {
          for (final h in g.hints) {
            final after = await engine.respond(before, h.de.replaceAll('…', 'Deniz'));
            expect(after.goalsDone, contains(g.id), reason: 'hint "${h.de}" did not reach ${g.id}');
          }
          before = await engine.respond(before, g.hints.first.de.replaceAll('…', 'Deniz'));
        }
      });
    }
  });
}
