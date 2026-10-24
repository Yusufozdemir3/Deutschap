import 'dart:math' as math;

import 'text/tokenizer.dart';

enum AnswerVerdict {
  /// Matches an accepted answer.
  correct,

  /// Matches except for capitalisation or umlaut spelling (ae/oe/ue/ss).
  correctWithNote,

  /// A small typo; the meaning and structure are right.
  nearMiss,
  wrong;

  bool get isAccepted => this != wrong;
}

class AnswerCheck {
  const AnswerCheck(this.verdict, this.expected, {this.noteTr});
  final AnswerVerdict verdict;

  /// The accepted answer closest to the input.
  final String expected;
  final String? noteTr;
}

String normalizeAnswer(String s) => s
    .replaceAll('’', "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .replaceAll(RegExp(r'^[„“"»«]+|[„“"»«]+$'), '')
    .replaceAll(RegExp(r'\s*[.!?]+$'), '')
    .replaceAll(RegExp(r'\s+([,;:])'), r'$1')
    .trim();

/// Accepts every listed alternative; never forces one model sentence.
AnswerCheck checkAnswer(String input, List<String> accepted) {
  assert(accepted.isNotEmpty);
  final given = normalizeAnswer(input);
  if (given.isEmpty) return AnswerCheck(AnswerVerdict.wrong, accepted.first);

  for (final a in accepted) {
    final n = normalizeAnswer(a);
    if (n == given) return AnswerCheck(AnswerVerdict.correct, a);
    if (_firstUpper(n) == _firstUpper(given)) return AnswerCheck(AnswerVerdict.correct, a);
  }
  for (final a in accepted) {
    if (normalizeAnswer(a).toLowerCase() == given.toLowerCase()) {
      return AnswerCheck(
        AnswerVerdict.correctWithNote,
        a,
        noteTr: 'Büyük/küçük harfe dikkat: Almancada isimler büyük harfle yazılır. Doğrusu: "$a"',
      );
    }
  }
  for (final a in accepted) {
    if (fold(normalizeAnswer(a)) == fold(given)) {
      return AnswerCheck(
        AnswerVerdict.correctWithNote,
        a,
        noteTr: 'Kabul edildi. Özel harflerle yazımı: "$a" (ä, ö, ü, ß).',
      );
    }
  }

  var best = accepted.first;
  var bestDistance = 1 << 30;
  for (final a in accepted) {
    final d = levenshtein(fold(normalizeAnswer(a)), fold(given));
    if (d < bestDistance) {
      bestDistance = d;
      best = a;
    }
  }
  final target = fold(normalizeAnswer(best));
  final allowed = target.length < 5 ? 0 : math.min(2, 1 + target.length ~/ 12);
  if (bestDistance <= allowed && _sameWordCount(target, fold(given)) && !_differsInFunctionWord(target, fold(given))) {
    return AnswerCheck(AnswerVerdict.nearMiss, best, noteTr: 'Neredeyse! Küçük bir yazım hatası var. Doğrusu: "$best"');
  }
  return AnswerCheck(AnswerVerdict.wrong, best);
}

String _firstUpper(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

bool _sameWordCount(String a, String b) => a.split(' ').length == b.split(' ').length;

/// Articles, auxiliaries and prepositions carry grammar: "ein" vs "einen"
/// is a case error, not a typo, even though only one letter differs.
const _functionWords = {
  'ein', 'eine', 'einen', 'einem', 'einer', 'eines', 'kein', 'keine', 'keinen', 'keinem',
  'der', 'die', 'das', 'den', 'dem', 'des', 'mein', 'meine', 'meinen', 'dein', 'deine', 'deinen',
  'bin', 'bist', 'ist', 'sind', 'seid', 'habe', 'hast', 'hat', 'haben', 'habt',
  'am', 'um', 'im', 'in', 'an', 'zu', 'zum', 'zur', 'mit', 'aus', 'ins', 'auf',
};

bool _differsInFunctionWord(String a, String b) {
  final x = a.split(' ');
  final y = b.split(' ');
  for (var i = 0; i < x.length && i < y.length; i++) {
    final p = x[i].replaceAll(RegExp(r'[^a-z]'), '');
    final q = y[i].replaceAll(RegExp(r'[^a-z]'), '');
    if (p != q && (_functionWords.contains(p) || _functionWords.contains(q))) return true;
  }
  return false;
}

int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var prev = List<int>.generate(b.length + 1, (i) => i);
  var cur = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
    }
    final t = prev;
    prev = cur;
    cur = t;
  }
  return prev[b.length];
}
