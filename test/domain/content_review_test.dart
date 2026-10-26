import 'package:deutschap/features/content_review/domain/review_items.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';

void main() {
  final content = loadTestContent();
  final items = collectReviewItems(content);

  test('every area has items and ids are unique', () {
    for (final a in ReviewArea.values) {
      expect(items.where((i) => i.area == a), isNotEmpty, reason: a.name);
    }
    final ids = <String>{};
    final dupes = [for (final i in items) if (!ids.add(i.id)) i.id];
    expect(dupes, isEmpty);
  });

  test('every lexeme and reading paragraph is reviewable', () {
    expect(items.where((i) => i.id.startsWith('lex:') && !i.id.contains(':ex')).length, content.lexicon.length);
    expect(items.where((i) => i.area == ReviewArea.reading).length, content.readings.fold<int>(0, (n, r) => n + r.paragraphs.length));
  });

  test('the report lists only flagged items, with notes, one per line', () {
    final marks = {
      items[0].id: const ReviewMark(ReviewVerdict.ok),
      items[1].id: const ReviewMark(ReviewVerdict.issue, note: 'Artikel\tfalsch'),
    };
    final lines = reviewReportTsv(items, marks).trim().split('\n');
    expect(lines.length, 2);
    expect(lines[1], startsWith(items[1].id));
    expect(lines[1], endsWith('issue\tArtikel falsch'));
    expect(ReviewMark.fromJson(marks[items[1].id]!.toJson().cast()).note, 'Artikel\tfalsch');
  });
}
