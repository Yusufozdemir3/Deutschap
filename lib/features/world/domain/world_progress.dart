import '../../../content/models/world.dart';
import '../../vocabulary/domain/vocab_status.dart';

/// What the learner has demonstrably done. Built from the database; all
/// map, clue and milestone logic is a pure function of these facts.
class ProgressFacts {
  const ProgressFacts({
    this.lessons = const {},
    this.episodeNumbers = const {},
    this.scenarios = const {},
    this.readings = const {},
    this.listenings = const {},
    this.unaidedRecalls = 0,
    this.unaidedArticles = 0,
    this.unaidedProductions = 0,
    this.statusCounts = const {},
    this.recalledLexemes = const {},
    this.savedLexemes = const {},
  });

  final Set<String> lessons;

  /// Completed story episode numbers (any level variant).
  final Set<int> episodeNumbers;
  final Set<String> scenarios;
  final Set<String> readings;
  final Set<String> listenings;
  final int unaidedRecalls;
  final int unaidedArticles;
  final int unaidedProductions;
  final Map<VocabStatus, int> statusCounts;

  /// Lexemes recalled at least once without help.
  final Set<String> recalledLexemes;
  final Set<String> savedLexemes;

  int countAtLeast(VocabStatus s) {
    const order = [
      VocabStatus.familiar,
      VocabStatus.temporarilyMastered,
      VocabStatus.longTermRetained,
    ];
    final from = order.indexOf(s);
    if (from < 0) return 0;
    return order.skip(from).fold(0, (sum, x) => sum + (statusCounts[x] ?? 0));
  }

  bool satisfies(UnlockRef r) => switch (r.kind) {
        'lesson' => lessons.contains(r.id),
        'episode' => episodeNumbers.contains(int.tryParse(r.id)),
        'scenario' => scenarios.contains(r.id),
        'reading' => readings.contains(r.id),
        'listening' => listenings.contains(r.id),
        _ => false,
      };
}

bool isUnlocked(Place p, ProgressFacts f) => p.unlock.any(f.satisfies);

enum ClueState {
  /// Its episode is not finished yet.
  hidden,

  /// Revealed by the story.
  revealed,

  /// All its words were recalled without help: the learner owns the clue.
  solved,
}

ClueState clueState(Clue c, ProgressFacts f) {
  if (!f.episodeNumbers.contains(c.episode)) return ClueState.hidden;
  return c.lexemes.every(f.recalledLexemes.contains) ? ClueState.solved : ClueState.revealed;
}

/// A milestone for a real, demonstrated ability. Few and meaningful;
/// nothing for logging in or tapping.
class Milestone {
  const Milestone({
    required this.id,
    required this.icon,
    required this.titleTr,
    required this.descriptionTr,
    required this.target,
    required this.progress,
  });

  final String id;
  final String icon;
  final String titleTr;
  final String descriptionTr;
  final int target;
  final int Function(ProgressFacts f) progress;

  int current(ProgressFacts f) => progress(f).clamp(0, target);
  bool earned(ProgressFacts f) => progress(f) >= target;
}

int _has(bool b) => b ? 1 : 0;

const _a2Scenarios = {'arzt', 'apotheke', 'wohnung', 'bahnhof', 'kleidung', 'hotel', 'verabredung', 'vorstellungsgespraech', 'anmeldung', 'post', 'bank', 'friseur', 'handyvertrag'};

final milestones = <Milestone>[
  Milestone(id: 'first_lesson', icon: 'flag', titleTr: 'İlk adım', descriptionTr: 'İlk dersini tamamla.', target: 1, progress: (f) => f.lessons.length),
  Milestone(id: 'first_order', icon: 'cafe', titleTr: 'İlk sipariş', descriptionTr: 'Fırında ya da kafede bir konuşmayı baştan sona Almanca tamamla.', target: 1, progress: (f) => _has(f.scenarios.contains('cafe') || f.scenarios.contains('baeckerei'))),
  Milestone(id: 'phone_call', icon: 'phone', titleTr: 'Telefonda randevu', descriptionTr: 'Telefonla randevu alma senaryosunu tamamla.', target: 1, progress: (f) => _has(f.scenarios.contains('termin'))),
  Milestone(id: 'all_scenarios', icon: 'forum', titleTr: 'Gerçek hayata hazır', descriptionTr: 'Altı farklı gerçek hayat senaryosunu tamamla.', target: 6, progress: (f) => f.scenarios.length),
  Milestone(id: 'story_season', icon: 'book', titleTr: 'Kartpostalın peşinde', descriptionTr: '"Neu in Berlin"in beş bölümünü bitir.', target: 5, progress: (f) => f.episodeNumbers.length),
  Milestone(id: 'story_finale', icon: 'mail', titleTr: 'Kırk yıl sonra', descriptionTr: '"Neu in Berlin"in ilk sezonunu (8 bölüm) bitir.', target: 8, progress: (f) => f.episodeNumbers.length),
  Milestone(id: 'detective', icon: 'search', titleTr: 'Dedektif', descriptionTr: 'Gizem panosundaki tüm ipuçlarını kelimeleriyle çöz.', target: 6, progress: (f) => 0), // computed from clues in evaluateMilestones
  Milestone(id: 'path_half', icon: 'route', titleTr: 'Yolun yarısı', descriptionTr: 'A1 yolunda 12 ders tamamla.', target: 12, progress: (f) => f.lessons.where((l) => RegExp(r'^u\d').hasMatch(l)).length),
  Milestone(id: 'path_done', icon: 'school', titleTr: 'A1 yolu tamam', descriptionTr: 'A1 yolunun 24 dersinin hepsini tamamla.', target: 24, progress: (f) => f.lessons.where((l) => RegExp(r'^u\d').hasMatch(l)).length),
  Milestone(id: 'a2_half', icon: 'route', titleTr: 'A2 yolunda', descriptionTr: 'A2 yolunda 12 ders tamamla.', target: 12, progress: (f) => f.lessons.where((l) => l.startsWith('a2')).length),
  Milestone(id: 'a2_done', icon: 'school', titleTr: 'A2 yolu tamam', descriptionTr: 'A2 yolunun 24 dersinin hepsini tamamla.', target: 24, progress: (f) => f.lessons.where((l) => l.startsWith('a2')).length),
  Milestone(id: 'a2_life', icon: 'forum', titleTr: 'Gündelik hayatta', descriptionTr: 'Dört farklı A2 senaryosunu tamamla (doktor, ev, tren, iş görüşmesi …).', target: 4, progress: (f) => f.scenarios.where(_a2Scenarios.contains).length),
  Milestone(id: 'listener_5', icon: 'reading', titleTr: 'Kulak aşinalığı', descriptionTr: 'Beş dinleme metninin sorularını cevapla.', target: 5, progress: (f) => f.listenings.length),
  Milestone(id: 'formal_email', icon: 'mail', titleTr: 'İlk resmî e-posta', descriptionTr: 'İş e-postası dersini tamamla.', target: 1, progress: (f) => _has(f.lessons.contains('u12l2'))),
  Milestone(id: 'recall_100', icon: 'memory', titleTr: '100 kez hatırladım', descriptionTr: 'Tekrarlarda 100 kez ipucu kullanmadan hatırla.', target: 100, progress: (f) => f.unaidedRecalls),
  Milestone(id: 'articles_25', icon: 'article', titleTr: 'Artikel ustası', descriptionTr: 'der/die/das kartlarında ipucusuz 25 doğru cevap ver.', target: 25, progress: (f) => f.unaidedArticles),
  Milestone(id: 'writer_10', icon: 'edit', titleTr: 'Kendi kelimelerimle', descriptionTr: 'Almancasını kendin yazarak 10 kelimeyi hatırla.', target: 10, progress: (f) => f.unaidedProductions),
  Milestone(id: 'familiar_25', icon: 'library', titleTr: '25 tanıdık kelime', descriptionTr: '25 kelimeyi en az "Tanıdık" seviyesine getir (bir haftadan uzun aralıklarla hatırlamak).', target: 25, progress: (f) => f.countAtLeast(VocabStatus.familiar)),
  Milestone(id: 'mastered_10', icon: 'star', titleTr: 'Oturan kelimeler', descriptionTr: '10 kelimeyi üç haftadan uzun aralıklarla hatırla.', target: 10, progress: (f) => f.countAtLeast(VocabStatus.temporarilyMastered)),
  Milestone(id: 'reader_3', icon: 'reading', titleTr: 'Okur', descriptionTr: 'Üç okuma metnini bitir.', target: 3, progress: (f) => f.readings.length),
  Milestone(id: 'explorer', icon: 'map', titleTr: 'Kiez kâşifi', descriptionTr: 'Mahalle haritasındaki tüm yerleri aç.', target: 11, progress: (f) => 0), // computed from places in evaluateMilestones
];

/// Milestones whose progress depends on content (places, clues).
typedef MilestoneStatus = ({Milestone milestone, int current, int target, bool earned});

List<MilestoneStatus> evaluateMilestones(
  ProgressFacts f, {
  required List<Place> places,
  required List<Clue> clues,
}) {
  final unlockedPlaces = places.where((p) => isUnlocked(p, f)).length;
  final solvedClues = clues.where((c) => clueState(c, f) == ClueState.solved).length;
  return [
    for (final m in milestones)
      switch (m.id) {
        'explorer' => (milestone: m, current: unlockedPlaces, target: places.length, earned: places.isNotEmpty && unlockedPlaces >= places.length),
        'detective' => (milestone: m, current: solvedClues, target: clues.length, earned: clues.isNotEmpty && solvedClues >= clues.length),
        _ => (milestone: m, current: m.current(f), target: m.target, earned: m.earned(f)),
      },
  ];
}
