/// Small typed accessors for content JSON. They throw [ContentFormatException]
/// with a path so a broken content file points at the exact field.
class ContentFormatException implements Exception {
  ContentFormatException(this.message);
  final String message;
  @override
  String toString() => 'ContentFormatException: $message';
}

typedef Json = Map<String, dynamic>;

extension JsonRead on Json {
  String str(String key, {String? where}) {
    final v = this[key];
    if (v is String) return v;
    throw ContentFormatException('${where ?? ''}.$key must be a string, got $v');
  }

  String? optStr(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is String) return v;
    throw ContentFormatException('.$key must be a string or null, got $v');
  }

  int integer(String key, {int? fallback}) {
    final v = this[key];
    if (v is int) return v;
    if (v == null && fallback != null) return fallback;
    throw ContentFormatException('.$key must be an int, got $v');
  }

  bool flag(String key, {bool fallback = false}) {
    final v = this[key];
    if (v is bool) return v;
    return fallback;
  }

  List<String> strList(String key) {
    final v = this[key];
    if (v == null) return const [];
    if (v is List) return v.map((e) => e as String).toList(growable: false);
    throw ContentFormatException('.$key must be a list of strings, got $v');
  }

  List<int> intList(String key) {
    final v = this[key];
    if (v == null) return const [];
    if (v is List) return v.map((e) => e as int).toList(growable: false);
    throw ContentFormatException('.$key must be a list of ints, got $v');
  }

  List<Json> objList(String key) {
    final v = this[key];
    if (v == null) return const [];
    if (v is List) return v.map((e) => (e as Map).cast<String, dynamic>()).toList(growable: false);
    throw ContentFormatException('.$key must be a list of objects, got $v');
  }

  Json? optObj(String key) {
    final v = this[key];
    if (v == null) return null;
    if (v is Map) return v.cast<String, dynamic>();
    throw ContentFormatException('.$key must be an object, got $v');
  }
}
