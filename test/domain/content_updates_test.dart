import 'dart:convert';

import 'package:deutschap/content/content_bundle.dart';
import 'package:deutschap/content/content_updates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../helpers/test_content.dart';

void main() {
  final bundled = loadContentSources();

  String withExtraText(String id) {
    final j = jsonDecode(bundled['reading.json']!) as Map<String, dynamic>;
    (j['texts'] as List).add({
      'id': id,
      'title': 'Neu',
      'level': 'A1',
      'minutes': 1,
      'topic_tr': 'Test',
      'paragraphs': [
        {'de': 'Das ist neu.', 'tr': 'Bu yeni.'},
      ],
      'questions': <Object>[],
    });
    return jsonEncode(j);
  }

  MockClient server(Map<String, String> files) => MockClient((r) async {
        final body = files[r.url.path];
        return body == null ? http.Response('nope', 404) : http.Response.bytes(utf8.encode(body), 200);
      });

  test('a valid update is downloaded, checked and returned', () async {
    final client = server({
      '/m.json': jsonEncode({'format': 1, 'version': '2026.11.1', 'notes_tr': 'Yeni metin', 'files': {'reading.json': 'reading.json'}}),
      '/reading.json': withExtraText('r_update_test'),
    });
    final update = await ContentUpdater(client: client).fetch('https://example.org/m.json', bundled: bundled);
    expect(update.version, '2026.11.1');
    expect(update.files.keys, ['reading.json']);
    final merged = ContentBundle.fromSources({...bundled, ...update.files});
    expect(merged.reading('r_update_test'), isNotNull);
  });

  test('broken, unknown or insecure updates are refused', () async {
    final broken = server({
      '/m.json': jsonEncode({'format': 1, 'files': {'reading.json': 'reading.json'}}),
      '/reading.json': '{"texts": [{"id": "x"}]}',
    });
    await expectLater(ContentUpdater(client: broken).fetch('https://e.org/m.json', bundled: bundled), throwsA(isA<ContentUpdateException>()));

    final unknownFile = server({'/m.json': jsonEncode({'format': 1, 'files': {'evil.dart': 'x'}})});
    await expectLater(ContentUpdater(client: unknownFile).fetch('https://e.org/m.json', bundled: bundled), throwsA(isA<ContentUpdateException>()));

    await expectLater(ContentUpdater(client: server({})).fetch('http://e.org/m.json', bundled: bundled), throwsA(isA<ContentUpdateException>()));
    expect(ContentUpdater.allowedUrl(Uri.parse('http://localhost:8080/m.json')), isTrue);

    final duplicate = server({
      '/m.json': jsonEncode({'format': 1, 'files': {'reading.json': 'reading.json'}}),
      '/reading.json': withExtraText('r_mein_zimmer'),
    });
    await expectLater(ContentUpdater(client: duplicate).fetch('https://e.org/m.json', bundled: bundled), throwsA(isA<ContentUpdateException>()),
        reason: 'the validator catches a duplicate reading id');
  });
}
