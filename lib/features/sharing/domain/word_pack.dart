import 'dart:convert';

/// A word not in the app's dictionary, added by a teacher or learner.
class CustomWord {
  const CustomWord({required this.headword, required this.meaningTr, this.example});
  final String headword;
  final String meaningTr;
  final String? example;

  Map<String, Object?> toJson() => {'h': headword, 't': meaningTr, if (example != null && example!.isNotEmpty) 'e': example};

  static CustomWord? fromJson(Object? j) {
    if (j is! Map) return null;
    final h = j['h'], t = j['t'], e = j['e'];
    if (h is! String || t is! String || h.trim().isEmpty || t.trim().isEmpty) return null;
    return CustomWord(headword: _clip(h, 80), meaningTr: _clip(t, 120), example: e is String ? _clip(e, 200) : null);
  }
}

String _clip(String s, int max) => s.trim().length > max ? s.trim().substring(0, max) : s.trim();

/// A shareable word list: a learner's collection or a teacher's pack.
/// Travels as a short text code (also inside a QR code or a link), so no
/// account or server is needed. Only word ids, words and meanings are
/// included – never learning progress.
class WordPack {
  const WordPack({required this.name, this.note, this.lexemeIds = const [], this.custom = const [], this.teacher = false});

  final String name;
  final String? note;
  final List<String> lexemeIds;
  final List<CustomWord> custom;

  /// Prepared in teacher mode (shown to the student on import).
  final bool teacher;

  int get size => lexemeIds.length + custom.length;

  static const prefix = 'DSP1:';
  static const maxWords = 300;

  /// Link that opens the import screen in the app (Android app link).
  String get link => 'deutschap://app/import?c=${Uri.encodeQueryComponent(encode())}';

  String encode() {
    final json = jsonEncode({
      'n': name,
      if (note != null && note!.isNotEmpty) 'o': note,
      if (lexemeIds.isNotEmpty) 'l': lexemeIds,
      if (custom.isNotEmpty) 'c': [for (final c in custom) c.toJson()],
      if (teacher) 'p': 1,
    });
    return prefix + base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  }

  /// Finds a pack code anywhere in [text] (a pasted message or a link) and
  /// decodes it. Returns null for anything that is not a valid pack.
  static WordPack? decode(String text) {
    final m = RegExp(r'DSP1(?::|%3A)([A-Za-z0-9_-]+)').firstMatch(text);
    if (m == null) return null;
    try {
      final raw = m.group(1)!;
      final padded = raw + '=' * ((4 - raw.length % 4) % 4);
      final j = jsonDecode(utf8.decode(base64Url.decode(padded)));
      if (j is! Map) return null;
      final name = j['n'];
      if (name is! String || name.trim().isEmpty) return null;
      final ids = [for (final x in (j['l'] as List?) ?? const []) if (x is String && RegExp(r'^[a-z0-9_]{1,40}$').hasMatch(x)) x];
      final custom = [for (final x in (j['c'] as List?) ?? const []) ?CustomWord.fromJson(x)];
      if (ids.length + custom.length == 0 || ids.length + custom.length > maxWords) return null;
      final note = j['o'];
      return WordPack(
        name: _clip(name, 60),
        note: note is String ? _clip(note, 300) : null,
        lexemeIds: ids,
        custom: custom,
        teacher: j['p'] == 1,
      );
    } on FormatException {
      return null;
    }
  }
}
