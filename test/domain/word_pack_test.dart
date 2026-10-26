import 'package:deutschap/features/sharing/domain/word_pack.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const pack = WordPack(
    name: 'Doktorda',
    note: 'Pazartesiye kadar çalışın.',
    lexemeIds: ['kopf', 'fieber', 'arzt'],
    custom: [CustomWord(headword: 'die Überweisung', meaningTr: 'sevk', example: 'Ich brauche eine Überweisung.')],
    teacher: true,
  );

  test('a pack survives encoding, also inside a message or a link', () {
    final code = pack.encode();
    expect(code, startsWith(WordPack.prefix));
    for (final text in [code, 'Merhaba! İşte liste:\n$code\nGörüşürüz', pack.link]) {
      final back = WordPack.decode(text)!;
      expect(back.name, 'Doktorda');
      expect(back.note, pack.note);
      expect(back.lexemeIds, pack.lexemeIds);
      expect(back.custom.single.headword, 'die Überweisung');
      expect(back.custom.single.example, 'Ich brauche eine Überweisung.');
      expect(back.teacher, isTrue);
    }
  });

  test('invalid or hostile codes are rejected', () {
    expect(WordPack.decode('hello'), isNull);
    expect(WordPack.decode('DSP1:!!!'), isNull);
    expect(WordPack.decode('DSP1:e30'), isNull, reason: '{} has no name and no words');
    final tooMany = WordPack(name: 'x', lexemeIds: List.generate(WordPack.maxWords + 1, (i) => 'w$i')).encode();
    expect(WordPack.decode(tooMany), isNull);
    final badIds = const WordPack(name: 'x', lexemeIds: ['ok', '../etc', 'DROP TABLE']).encode();
    expect(WordPack.decode(badIds)!.lexemeIds, ['ok']);
  });
}
