import '../../../content/models/story.dart';
import '../../../learning/text/lexicon.dart';
import '../../../learning/text/tokenizer.dart';

/// Fills the learner's name into story text.
String fillName(String text, String? name) => text.replaceAll('{name}', (name == null || name.trim().isEmpty) ? 'Deniz' : name.trim());

/// German text of every node and choice, with its translation.
List<({String de, String tr})> episodeLines(Episode e) => [
      for (final n in e.nodes.values)
        ...switch (n) {
          NarrationNode(:final de, :final tr) || LineNode(:final de, :final tr) => [(de: de, tr: tr)],
          ChoiceNode(:final choices) => [for (final c in choices) if (c.verdict != ChoiceVerdict.wrong) (de: c.de, tr: c.tr)],
          _ => const <({String de, String tr})>[],
        },
    ];

/// The first sentence of the episode in which [lexemeId] occurs, so a
/// word saved from the recap still keeps its story context.
({String de, String tr})? findOccurrence(Episode e, String lexemeId, Lexicon lexicon) {
  for (final line in episodeLines(e)) {
    final ws = words(line.de);
    final lower = ws.map((w) => w.toLowerCase()).toList();
    for (var i = 0; i < ws.length; i++) {
      final hit = lexicon.lookupWord(ws[i], sentenceWords: lower, wordIndex: i).lexemes.any((l) => l.id == lexemeId) ||
          lexicon.phrasesAt(ws, i).any((p) => p.lexeme.id == lexemeId);
      if (hit) return line;
    }
  }
  return null;
}
