import '../../content/models/lexeme.dart';
import 'tokenizer.dart';

enum LookupConfidence {
  /// The surface form is listed for the lexeme.
  exact,

  /// Derived by stripping a common ending; shown with an uncertainty note.
  guess,
}

class LookupResult {
  const LookupResult(this.lexemes, this.confidence);
  final List<Lexeme> lexemes;
  final LookupConfidence confidence;
  bool get isEmpty => lexemes.isEmpty;
}

class PhraseMatch {
  const PhraseMatch(this.lexeme, this.firstWord, this.lastWord);
  final Lexeme lexeme;

  /// Word indexes (see [TextToken.wordIndex]) covered by the phrase.
  final int firstWord;
  final int lastWord;
}

/// In-memory index over the curated lexicon. Only curated data is
/// returned; nothing is invented when a word is unknown.
class Lexicon {
  Lexicon(Iterable<Lexeme> lexemes) {
    for (final l in lexemes) {
      _byId[l.id] = l;
      if (l.isMultiWord) {
        for (final f in {l.lemma, ...l.forms}) {
          _phrases.add((words(f).map((w) => w.toLowerCase()).toList(), l));
        }
      } else {
        for (final f in {l.lemma, ...l.forms}) {
          (_byForm[f.toLowerCase()] ??= []).add(l);
        }
      }
    }
    _phrases.sort((a, b) => b.$1.length.compareTo(a.$1.length));
  }

  final _byId = <String, Lexeme>{};
  final _byForm = <String, List<Lexeme>>{};
  final _phrases = <(List<String>, Lexeme)>[];

  Iterable<Lexeme> get all => _byId.values;
  int get length => _byId.length;
  Lexeme? byId(String id) => _byId[id];
  bool contains(String id) => _byId.containsKey(id);

  static const _endings = ['en', 'es', 'er', 'em', 'e', 'n', 's', 't', 'st'];

  /// Looks up a single word. [sentenceWords] (lower case) lets separable
  /// verbs win when their prefix appears later ("Ich stehe um 7 auf").
  LookupResult lookupWord(String surface, {List<String> sentenceWords = const [], int wordIndex = -1}) {
    final key = surface.toLowerCase();
    final exact = _byForm[key];
    if (exact != null && exact.isNotEmpty) {
      return LookupResult(_rankSeparable(exact, sentenceWords, wordIndex, key), LookupConfidence.exact);
    }
    for (final e in _endings) {
      if (key.length > e.length + 2 && key.endsWith(e)) {
        final stem = key.substring(0, key.length - e.length);
        final hit = _byForm[stem] ?? _byForm['${stem}en'];
        if (hit != null) return LookupResult(hit, LookupConfidence.guess);
      }
    }
    return const LookupResult([], LookupConfidence.exact);
  }

  List<Lexeme> _rankSeparable(List<Lexeme> candidates, List<String> sentence, int wordIndex, String surface) {
    if (candidates.length < 2 && candidates.every((c) => c.verb?.separablePrefix == null)) {
      return candidates;
    }
    bool prefixFollows(Lexeme l) {
      final prefix = l.verb?.separablePrefix?.toLowerCase();
      if (prefix == null) return false;
      // Infinitive and participle carry the prefix: "umsteigen", "umgestiegen".
      if (surface.startsWith(prefix)) return true;
      if (wordIndex < 0) return false;
      return sentence.skip(wordIndex + 1).contains(prefix);
    }

    // A separable verb's stem form ("stehe") only means "aufstehen" when
    // the prefix ("auf") appears later; otherwise it is not offered.
    return candidates.where((l) => l.verb?.separablePrefix == null || prefixFollows(l)).toList()
      ..sort((a, b) => (prefixFollows(b) ? 1 : 0) - (prefixFollows(a) ? 1 : 0));
  }

  /// Multi-word expressions in [sentenceWords] that cover [wordIndex].
  List<PhraseMatch> phrasesAt(List<String> sentenceWords, int wordIndex) {
    final lower = sentenceWords.map((w) => w.toLowerCase()).toList();
    final out = <PhraseMatch>[];
    final seen = <String>{};
    for (final (phrase, lexeme) in _phrases) {
      if (seen.contains(lexeme.id)) continue;
      final n = phrase.length;
      for (var s = wordIndex - n + 1; s <= wordIndex; s++) {
        if (s < 0 || s + n > lower.length) continue;
        var ok = true;
        for (var k = 0; k < n; k++) {
          if (lower[s + k] != phrase[k]) {
            ok = false;
            break;
          }
        }
        if (ok) {
          out.add(PhraseMatch(lexeme, s, s + n - 1));
          seen.add(lexeme.id);
          break;
        }
      }
    }
    return out;
  }

  /// Nouns by lower-case lemma or form: used by error detectors.
  Lexeme? nounForm(String surface) {
    for (final l in _byForm[surface.toLowerCase()] ?? const <Lexeme>[]) {
      if (l.isNoun) return l;
    }
    return null;
  }
}
