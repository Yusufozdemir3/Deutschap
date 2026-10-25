import 'package:deutschap/features/conversation/domain/error_detectors.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';

void main() {
  final detectors = ErrorDetectors(loadTestContent().lexicon);

  test('Perfekt auxiliary is checked within one sentence', () {
    expect(detectors.check('Am Nachmittag hat es geregnet. Deshalb sind sie ins Museum gegangen.').where((i) => i.ruleId == 'perfekt_sein'), isEmpty);
    expect(detectors.check('Ich habe gestern ins Kino gegangen.').where((i) => i.ruleId == 'perfekt_sein'), isNotEmpty);
  });

  test('listed lower-case forms of nouns are not capitalised', () {
    expect(detectors.check('Das Museum ist montags geschlossen.').where((i) => i.ruleId == 'noun_caps'), isEmpty);
    expect(detectors.check('Ich stelle die Lampe auf den Tisch.').where((i) => i.ruleId == 'noun_caps'), isEmpty);
  });
}
