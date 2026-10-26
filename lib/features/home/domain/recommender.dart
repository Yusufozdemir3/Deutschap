/// Kinds of activity the home screen can recommend.
enum ActivityKind { review, lesson, story, scenario, reading, discover, practice, listening }

class Recommendation {
  const Recommendation({
    required this.kind,
    required this.titleTr,
    required this.reasonTr,
    required this.route,
    required this.minutes,
  });

  final ActivityKind kind;
  final String titleTr;

  /// Why this is suggested; always shown so the learner can judge it.
  final String reasonTr;
  final String route;
  final int minutes;
}

class NamedRef {
  const NamedRef(this.id, this.title, {this.minutes = 5});
  final String id;
  final String title;
  final int minutes;
}

/// Everything the recommender looks at. Built from repositories; the
/// recommender itself is pure and unit-tested.
class LearnerSnapshot {
  const LearnerSnapshot({
    this.dueCards = 0,
    this.unreviewedSaved = 0,
    this.needsReinforcement = 0,
    this.productionGap = 0,
    this.nextLesson,
    this.nextEpisode,
    this.practiceScenario,
    this.lastKinds = const [],
    this.totalEntries = 0,
    this.recurringIssue,
    this.weakWords = 0,
    this.nextListening,
    this.openMistakes = 0,
    this.mistakesReviewedThisWeek = false,
  });

  final int dueCards;
  final int unreviewedSaved;
  final int needsReinforcement;

  /// Entries recognised reliably but failing in typed production.
  final int productionGap;
  final NamedRef? nextLesson;
  final NamedRef? nextEpisode;
  final NamedRef? practiceScenario;

  /// Most recent activity kinds, newest first (for variety).
  final List<ActivityKind> lastKinds;
  final int totalEntries;

  /// A practice topic whose error recurred since it was last practised:
  /// (route segment, Turkish title, occurrences).
  final (String, String, int)? recurringIssue;

  /// Words missed more often than not in vocabulary drills.
  final int weakWords;

  /// A listening track the learner has not finished yet.
  final NamedRef? nextListening;

  /// Mistakes not yet answered correctly, and whether the weekly review was done.
  final int openMistakes;
  final bool mistakesReviewedThisWeek;
}

class Recommender {
  const Recommender();

  /// Returns candidates ordered by value. The first is the primary
  /// recommendation; the rest are optional alternatives.
  List<Recommendation> recommend(LearnerSnapshot s) {
    final out = <({Recommendation r, double score})>[];

    if (s.dueCards > 0) {
      out.add((
        r: Recommendation(
          kind: ActivityKind.review,
          titleTr: '${s.dueCards} kelimeyi tekrar et',
          reasonTr: s.needsReinforcement > 0
              ? 'Tekrar zamanı gelmiş kelimeler var, ${s.needsReinforcement} tanesinde son seferde zorlandın. Unutmaya başlamadan hatırlamak kalıcılığı artırır.'
              : 'Bu kelimelerin tekrar zamanı geldi. Tam unutmadan önce hatırlamak en verimli tekrardır.',
          route: '/review',
          minutes: (s.dueCards / 6).ceil().clamp(1, 10),
        ),
        score: 50 + s.dueCards.clamp(0, 30).toDouble(),
      ));
    }

    if (s.unreviewedSaved >= 3 && s.dueCards == 0) {
      out.add((
        r: Recommendation(
          kind: ActivityKind.review,
          titleTr: 'Yeni kaydettiğin kelimelerle ilk tekrar',
          reasonTr: '${s.unreviewedSaved} kelimeyi kaydettin ama henüz hiç hatırlamayı denemedin. İlk tekrar, kelimeyi kısa süreli bellekten çıkarmanın ilk adımı.',
          route: '/review',
          minutes: 3,
        ),
        score: 45,
      ));
    }

    if (s.productionGap > 0 && s.practiceScenario != null) {
      out.add((
        r: Recommendation(
          kind: ActivityKind.scenario,
          titleTr: s.practiceScenario!.title,
          reasonTr: '${s.productionGap} kelimeyi görünce tanıyorsun ama kendin üretirken zorlanıyorsun. Bir konuşmada kullanmak, aktif hatırlamayı güçlendirir.',
          route: '/scenario/${s.practiceScenario!.id}',
          minutes: s.practiceScenario!.minutes,
        ),
        score: 40,
      ));
    }

    if (s.recurringIssue case (final topic, final title, final count) when count >= 2) {
      out.add((
        r: Recommendation(
          kind: ActivityKind.practice,
          titleTr: 'Odaklı alıştırma: $title',
          reasonTr: 'Son konuşmalarında bu hata $count kez görüldü. Kısa, hedefli bir alıştırma bu kalıbı oturtmaya yardım eder.',
          route: '/practice/$topic',
          minutes: 4,
        ),
        score: 42,
      ));
    }

    if (s.openMistakes >= 5 && !s.mistakesReviewedThisWeek) {
      out.add((
        r: Recommendation(
          kind: ActivityKind.practice,
          titleTr: 'Hatalarını düzelt (${s.openMistakes})',
          reasonTr: 'Hata defterinde düzeltilmemiş sorular birikti. Haftada bir kısa tur, aynı hataları tekrar yapmanı önler.',
          route: '/mistakes/review',
          minutes: 5,
        ),
        score: 41,
      ));
    }

    if (s.weakWords >= 3) {
      out.add((
        r: Recommendation(
          kind: ActivityKind.practice,
          titleTr: 'Zorlandığın ${s.weakWords} kelimeyle antrenman',
          reasonTr: 'Kelime antrenmanlarında bu kelimeleri çoğu zaman yanlış yaptın. Kısa bir tur, onları farklı alıştırma türleriyle yeniden çalıştırır.',
          route: '/drill/run?src=weak&mode=mixed&n=10',
          minutes: 4,
        ),
        score: 38,
      ));
    }

    if (s.nextLesson != null) {
      out.add((
        r: Recommendation(
          kind: ActivityKind.lesson,
          titleTr: s.nextLesson!.title,
          reasonTr: s.totalEntries == 0
              ? 'A1 yolunun ilk adımı. Kısa, sesli ve kendi hızında.'
              : 'Öğrenme yolunda sıradaki ders. Yeni bir konu, öncekilerin üzerine kurulu.',
          route: '/lesson/${s.nextLesson!.id}',
          minutes: s.nextLesson!.minutes,
        ),
        score: 35,
      ));
    }

    if (s.nextEpisode != null) {
      out.add((
        r: Recommendation(
          kind: ActivityKind.story,
          titleTr: s.nextEpisode!.title,
          reasonTr: 'Hikâye devam ediyor. Öğrendiklerini bağlam içinde görürsün; yeni kelimeleri tek dokunuşla kaydedebilirsin.',
          route: '/episode/${s.nextEpisode!.id}',
          minutes: s.nextEpisode!.minutes,
        ),
        score: 33,
      ));
    }

    if (s.practiceScenario != null && s.productionGap == 0) {
      out.add((
        r: Recommendation(
          kind: ActivityKind.scenario,
          titleTr: s.practiceScenario!.title,
          reasonTr: 'Öğrendiğin ifadeleri gerçekçi bir konuşmada dene. Hatalar sorun değil; önce anlaşılmak önemli.',
          route: '/scenario/${s.practiceScenario!.id}',
          minutes: s.practiceScenario!.minutes,
        ),
        score: 25,
      ));
    }

    if (s.nextListening != null) {
      out.add((
        r: Recommendation(
          kind: ActivityKind.listening,
          titleTr: 'Dinle: ${s.nextListening!.title}',
          reasonTr: 'Kulağını Almancaya alıştır: önce metne bakmadan dinle, soruları cevapla, sonra metni aç.',
          route: '/listen/${s.nextListening!.id}',
          minutes: s.nextListening!.minutes,
        ),
        score: 22,
      ));
    }

    // Variety: lower the score of what the learner just did twice in a row.
    final recent = s.lastKinds.take(2).toList();
    final adjusted = [
      for (final c in out)
        (
          r: c.r,
          score: c.score - (recent.length == 2 && recent.every((k) => k == c.r.kind) && c.r.kind != ActivityKind.review ? 20 : 0),
        ),
    ]..sort((a, b) => b.score.compareTo(a.score));

    return [for (final c in adjusted) c.r];
  }
}
