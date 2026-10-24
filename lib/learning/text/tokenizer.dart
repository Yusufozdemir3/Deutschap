/// Splits German text into word and non-word tokens while keeping offsets,
/// so the UI can render the original text exactly and make words tappable.
class TextToken {
  const TextToken(this.text, this.start, {required this.isWord, this.wordIndex = -1});
  final String text;
  final int start;
  final bool isWord;

  /// Position among word tokens only; -1 for spaces and punctuation.
  final int wordIndex;

  int get end => start + text.length;
}

final _word = RegExp(r"[\p{L}\p{M}]+(?:[-'’][\p{L}\p{M}]+)*", unicode: true);

List<TextToken> tokenize(String text) {
  final tokens = <TextToken>[];
  var cursor = 0;
  var wordIndex = 0;
  for (final m in _word.allMatches(text)) {
    if (m.start > cursor) {
      tokens.add(TextToken(text.substring(cursor, m.start), cursor, isWord: false));
    }
    tokens.add(TextToken(m.group(0)!, m.start, isWord: true, wordIndex: wordIndex++));
    cursor = m.end;
  }
  if (cursor < text.length) {
    tokens.add(TextToken(text.substring(cursor), cursor, isWord: false));
  }
  return tokens;
}

List<String> words(String text) => [for (final m in _word.allMatches(text)) m.group(0)!];

/// Sentence containing [offset]; used to store a saved word's context.
String sentenceAround(String text, int offset) {
  final enders = RegExp(r'[.!?…]|\n');
  var start = 0;
  for (final m in enders.allMatches(text)) {
    if (m.end <= offset) start = m.end;
  }
  var end = text.length;
  for (final m in enders.allMatches(text, offset)) {
    end = m.end;
    break;
  }
  return text.substring(start, end).trim();
}

/// Lower case and ASCII-folded form used for lenient comparison.
String fold(String s) => s
    .toLowerCase()
    .replaceAll('ä', 'ae')
    .replaceAll('ö', 'oe')
    .replaceAll('ü', 'ue')
    .replaceAll('ß', 'ss')
    .replaceAll('’', "'");
