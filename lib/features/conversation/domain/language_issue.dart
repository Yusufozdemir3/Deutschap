/// Categories the feedback distinguishes. "Understood or not" is tracked
/// separately on the turn: a sentence can be understood and still contain
/// an error.
enum IssueKind {
  grammar('Dil bilgisi'),
  vocabulary('Kelime'),
  wordOrder('Kelime sırası'),
  spelling('Yazım'),
  register('Hitap / resmiyet'),
  style('Daha doğal');

  const IssueKind(this.labelTr);
  final String labelTr;

  /// Lower comes first when feedback is limited.
  int get priority => index;
}

enum IssueSeverity {
  /// A definite error.
  error,

  /// Valid German, but there is a more natural or polite option.
  suggestion,
}

class LanguageIssue {
  const LanguageIssue({
    required this.kind,
    required this.severity,
    required this.original,
    required this.corrected,
    required this.explanationTr,
    required this.ruleId,
  });

  final IssueKind kind;
  final IssueSeverity severity;
  final String original;

  /// Full corrected sentence (or the suggested alternative).
  final String corrected;
  final String explanationTr;

  /// Detector id; recorded so recurring errors can drive practice.
  final String ruleId;

  Map<String, Object?> toJson() => {
        'kind': kind.name,
        'severity': severity.name,
        'original': original,
        'corrected': corrected,
        'explanation_tr': explanationTr,
        'rule': ruleId,
      };

  factory LanguageIssue.fromJson(Map<String, dynamic> j) => LanguageIssue(
        kind: IssueKind.values.byName(j['kind'] as String),
        severity: IssueSeverity.values.byName(j['severity'] as String),
        original: j['original'] as String,
        corrected: j['corrected'] as String,
        explanationTr: j['explanation_tr'] as String,
        ruleId: j['rule'] as String,
      );
}
