import 'package:deutschap/features/conversation/domain/error_detectors.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';

void main() {
  final lexicon = loadTestContent().lexicon;
  final detectors = ErrorDetectors(lexicon);

  test('Perfekt auxiliary is checked within one sentence', () {
    expect(detectors.check('Am Nachmittag hat es geregnet. Deshalb sind sie ins Museum gegangen.').where((i) => i.ruleId == 'perfekt_sein'), isEmpty);
    expect(detectors.check('Ich habe gestern ins Kino gegangen.').where((i) => i.ruleId == 'perfekt_sein'), isNotEmpty);
    expect(detectors.check('Ich habe Freunde gefunden, und mein Deutsch ist besser geworden.').where((i) => i.ruleId == 'perfekt_sein'), isEmpty);
  });

  test('listed lower-case forms of nouns are not capitalised', () {
    expect(detectors.check('Das Museum ist montags geschlossen.').where((i) => i.ruleId == 'noun_caps'), isEmpty);
    expect(detectors.check('Ich stelle die Lampe auf den Tisch.').where((i) => i.ruleId == 'noun_caps'), isEmpty);
  });

  test('separable verbs resolve from infinitive, participle and split forms', () {
    expect(lexicon.lookupWord('umsteigen').lexemes.map((l) => l.id), contains('umsteigen'));
    expect(lexicon.lookupWord('umgestiegen').lexemes.map((l) => l.id), contains('umsteigen'));
    final ws = ['der', 'zug', 'fährt', 'um', 'acht', 'ab'];
    expect(lexicon.lookupWord('fährt', sentenceWords: ws, wordIndex: 2).lexemes.first.id, 'abfahren');
    expect(lexicon.lookupWord('fährt', sentenceWords: ['er', 'fährt', 'nach', 'berlin'], wordIndex: 1).lexemes.map((l) => l.id), isNot(contains('abfahren')));
  });
}
