import '../json_utils.dart';
import 'lexeme.dart';

/// A grammar concept with several ways in: rule, pattern table, examples,
/// a Turkish comparison and a typical mistake.
class GrammarConcept {
  const GrammarConcept({
    required this.id,
    required this.titleTr,
    required this.level,
    required this.ruleTr,
    this.requires = const [],
    this.table = const [],
    this.examples = const [],
    this.turkishCompareTr,
    this.mistake,
  });

  final String id;
  final String titleTr;
  final String level;
  final List<String> requires;
  final String ruleTr;

  /// Rows of a small pattern table; the first row is the header.
  final List<List<String>> table;
  final List<Example> examples;
  final String? turkishCompareTr;
  final CommonMistake? mistake;

  factory GrammarConcept.fromJson(Json j) {
    final m = j.optObj('mistake');
    final rawTable = j['table'];
    return GrammarConcept(
      id: j.str('id'),
      titleTr: j.str('title_tr'),
      level: j.str('level'),
      requires: j.strList('requires'),
      ruleTr: j.str('rule_tr'),
      table: rawTable is List
          ? rawTable.map((r) => (r as List).map((c) => c as String).toList(growable: false)).toList(growable: false)
          : const [],
      examples: j.objList('examples').map(Example.fromJson).toList(growable: false),
      turkishCompareTr: j.optStr('turkish_tr'),
      mistake: m == null ? null : CommonMistake.fromJson(m),
    );
  }
}

class CommonMistake {
  const CommonMistake({required this.wrong, required this.right, required this.explainTr});
  final String wrong;
  final String right;
  final String explainTr;

  factory CommonMistake.fromJson(Json j) =>
      CommonMistake(wrong: j.str('wrong'), right: j.str('right'), explainTr: j.str('explain_tr'));
}
