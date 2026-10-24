import '../../review/domain/scheduler.dart';

/// Learning status shown to the learner. Derived from review evidence,
/// never from a single answer. See docs/REVIEW_ENGINE.md.
enum VocabStatus {
  newlyEncountered('new', 'Yeni'),
  savedForLater('later', 'Sonraya saklandı'),
  learning('learning', 'Öğreniliyor'),
  needsReinforcement('reinforce', 'Pekiştirilmeli'),
  familiar('familiar', 'Tanıdık'),
  temporarilyMastered('mastered', 'Şimdilik oturdu'),
  longTermRetained('retained', 'Kalıcı');

  const VocabStatus(this.key, this.labelTr);
  final String key;
  final String labelTr;

  static VocabStatus parse(String key) =>
      VocabStatus.values.firstWhere((s) => s.key == key, orElse: () => VocabStatus.newlyEncountered);

  String get explanationTr => switch (this) {
        newlyEncountered => 'Henüz tekrar etmedin.',
        savedForLater => 'Tekrar planına alınmadı; istediğinde başlatabilirsin.',
        learning => 'İlk tekrarlar sürüyor; aralıklar henüz kısa.',
        needsReinforcement => 'Son tekrarda zorlandın; yakında tekrar gelecek.',
        familiar => 'Bir haftadan uzun aralıklarla hatırlıyorsun.',
        temporarilyMastered => 'Üç haftadan uzun aralıklarla hatırlıyorsun. Kalıcılık için gecikmeli tekrarlar sürecek.',
        longTermRetained => 'Uzun aralıklarla, farklı alıştırma türlerinde, ipucusuz hatırladın.',
      };
}

/// Pure status derivation.
///
/// [delayedUnaidedSuccesses] counts unaided successful reviews whose
/// previous interval was at least 21 days (real delayed retention).
VocabStatus deriveStatus({
  required bool paused,
  required List<CardState> cards,
  required int delayedUnaidedSuccesses,
}) {
  if (paused) return VocabStatus.savedForLater;
  final reviewed = cards.where((c) => c.lastReviewedAt != null).toList();
  if (reviewed.isEmpty) return VocabStatus.newlyEncountered;

  if (reviewed.any((c) => c.lastGrade == Grade.again)) {
    return VocabStatus.needsReinforcement;
  }
  final minInterval = cards.map((c) => c.reps == 0 ? 0.0 : c.intervalDays).reduce((a, b) => a < b ? a : b);
  final lapses = cards.fold<int>(0, (sum, c) => sum + c.lapses);
  if (lapses >= 3 && minInterval < 21) return VocabStatus.needsReinforcement;
  if (minInterval < 7) return VocabStatus.learning;
  if (minInterval < 21) return VocabStatus.familiar;
  if (minInterval >= 60 && delayedUnaidedSuccesses >= 2 && cards.length >= 2) {
    return VocabStatus.longTermRetained;
  }
  return VocabStatus.temporarilyMastered;
}
