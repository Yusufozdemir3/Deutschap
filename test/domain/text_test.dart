import 'package:deutschap/learning/answer_checker.dart';
import 'package:deutschap/learning/text/lexicon.dart';
import 'package:deutschap/learning/text/tokenizer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';

void main() {
  final lexicon = loadTestContent().lexicon;

  group('tokenizer', () {
    test('keeps offsets and punctuation', () {
      const text = 'Hallo! Wie geht\'s, Lina?';
      final t = tokenize(text);
      expect(t.map((x) => x.text).join(), text);
      expect(t.where((x) => x.isWord).map((x) => x.text), ['Hallo', 'Wie', "geht's", 'Lina']);
      expect(t.firstWhere((x) => x.text == 'Lina').wordIndex, 3);
    });

    test('handles umlauts, ß and hyphens', () {
      expect(words('Die U-Bahn fährt zur Straße.'), ['Die', 'U-Bahn', 'fährt', 'zur', 'Straße']);
    });

    test('finds the surrounding sentence', () {
      const text = 'Ich bin neu. Wo ist der Bahnhof? Danke!';
      expect(sentenceAround(text, text.indexOf('Bahnhof')), 'Wo ist der Bahnhof?');
    });
  });

  group('lexicon lookup', () {
    test('inflected forms resolve to the lemma', () {
      expect(lexicon.lookupWord('Städte').lexemes.single.id, 'stadt');
      expect(lexicon.lookupWord('nimmt').lexemes.single.id, 'nehmen');
      expect(lexicon.lookupWord('nimmt').confidence, LookupConfidence.exact);
    });

    test('ambiguous forms return every candidate', () {
      final ids = lexicon.lookupWord('morgen').lexemes.map((l) => l.id).toSet();
      expect(ids, containsAll(['morgen_adv', 'morgen_noun']));
    });

    test('separable verbs are only offered when the prefix follows', () {
      final s = words('Ich stehe um sieben Uhr auf').map((w) => w.toLowerCase()).toList();
      expect(lexicon.lookupWord('stehe', sentenceWords: s, wordIndex: 1).lexemes.first.id, 'aufstehen');
      final s2 = words('Du stehst vor der Tür').map((w) => w.toLowerCase()).toList();
      expect(lexicon.lookupWord('stehst', sentenceWords: s2, wordIndex: 1).lexemes.map((l) => l.id), ['stehen']);
    });

    test('unknown words return nothing instead of a guess', () {
      expect(lexicon.lookupWord('Quantenphysik').isEmpty, isTrue);
    });

    test('multi-word expressions are detected around a tapped word', () {
      final s = words('Ich möchte einen Termin vereinbaren.');
      final phrases = lexicon.phrasesAt(s, 3);
      expect(phrases.map((p) => p.lexeme.id), contains('termin_vereinbaren'));
      final m = phrases.firstWhere((p) => p.lexeme.id == 'termin_vereinbaren');
      expect((m.firstWord, m.lastWord), (2, 4));
    });

    test('nouns always carry their article in the headword', () {
      expect(lexicon.byId('termin')!.headword, 'der Termin');
      expect(lexicon.byId('broetchen')!.headword, 'das Brötchen');
    });
  });

  group('answer checker', () {
    test('accepts any listed alternative and ignores final punctuation', () {
      final r = checkAnswer('Mein Name ist Can, freut mich',['Ich heiße Can. Freut mich!', 'Mein Name ist Can, freut mich!']);
      expect(r.verdict, AnswerVerdict.correct);
    });

    test('umlaut transliteration is accepted with a note', () {
      final r = checkAnswer('Wir fruehstuecken zusammen', ['Wir frühstücken zusammen.']);
      expect(r.verdict, AnswerVerdict.correctWithNote);
      expect(r.noteTr, contains('frühstücken'));
    });

    test('lower-case nouns are accepted with a capitalisation note', () {
      final r = checkAnswer('die rechnung, bitte', ['Die Rechnung, bitte.']);
      expect(r.verdict, AnswerVerdict.correctWithNote);
    });

    test('a one-letter typo is a near miss, not a pass', () {
      final r = checkAnswer('Ich hätte gern einen Kafee', ['Ich hätte gern einen Kaffee.']);
      expect(r.verdict, AnswerVerdict.nearMiss);
    });

    test('a grammatical error is wrong', () {
      final r = checkAnswer('Ich hätte gern ein Kaffee', ['Ich hätte gern einen Kaffee.']);
      expect(r.verdict, AnswerVerdict.wrong);
    });

    test('short answers get no typo tolerance', () {
      expect(checkAnswer('dre', ['drei']).verdict, AnswerVerdict.wrong);
    });
  });
}
