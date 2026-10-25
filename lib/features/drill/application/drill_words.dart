import 'dart:math';

import '../../../content/content_bundle.dart';
import '../../../content/models/lesson.dart';
import '../../../content/models/lexeme.dart';
import '../../progress/data/progress_repository.dart';
import '../../vocabulary/data/vocab_repository.dart';
import '../domain/vocab_drill.dart';

/// Words a learner keeps missing in drills: more misses than hits.
Future<List<String>> weakLexemeIds(ProgressRepository progress, {DateTime? since}) async {
  final stats = await progress.itemStats('drill', since: since);
  final byLexeme = <String, ({int right, int wrong})>{};
  for (final e in stats.entries) {
    final id = lexemeOfDrillItem(e.key);
    final prev = byLexeme[id] ?? (right: 0, wrong: 0);
    byLexeme[id] = (right: prev.right + e.value.right, wrong: prev.wrong + e.value.wrong);
  }
  final weak = byLexeme.entries.where((e) => e.value.wrong > 0 && e.value.wrong >= e.value.right).toList()
    ..sort((a, b) => (b.value.wrong - b.value.right).compareTo(a.value.wrong - a.value.right));
  return [for (final e in weak) e.key];
}

/// Resolves a [DrillSpec.source] to lexemes, most useful first.
Future<List<Lexeme>> resolveDrillWords(
  DrillSpec spec, {
  required ContentBundle content,
  required VocabRepository vocab,
  required ProgressRepository progress,
  required int seed,
}) async {
  final rnd = Random(seed);
  final lex = content.lexicon;
  List<Lexeme> shuffled(Iterable<Lexeme> xs) => (xs.toList()..sort((a, b) => a.id.compareTo(b.id)))..shuffle(rnd);
  final src = spec.source;
  if (src == 'saved') {
    return shuffled((await vocab.savedLexemeIds()).map(lex.byId).whereType<Lexeme>());
  }
  if (src.startsWith('collection:')) {
    return shuffled((await vocab.collectionLexemeIds(src.substring('collection:'.length))).map(lex.byId).whereType<Lexeme>());
  }
  if (src == 'weak') {
    return [for (final id in await weakLexemeIds(progress)) ?lex.byId(id)];
  }
  final (kind, value) = switch (src.indexOf(':')) {
    -1 => (src, ''),
    final i => (src.substring(0, i), src.substring(i + 1)),
  };
  return switch (kind) {
    'level' => shuffled(lex.all.where((l) => l.cefr == value)),
    'tag' => shuffled(lex.all.where((l) => l.tags.contains(value))),
    'unit' => shuffled({
        for (final l in content.unit(value)?.lessons ?? const <Lesson>[]) ...l.vocab,
      }.map(lex.byId).whereType<Lexeme>()),
    _ => shuffled(lex.all),
  };
}

/// Turkish labels for the topic tags used in the lexicon.
const drillTagLabels = {
  'essen': 'Yemek ve içecek',
  'alltag': 'Günlük hayat',
  'zahlen': 'Sayılar',
  'stadt': 'Şehir',
  'zeit': 'Zaman',
  'begruessung': 'Selamlaşma',
  'buerokratie': 'Resmî işler',
  'arbeit': 'İş',
  'kultur': 'Kültür',
  'kommunikation': 'İletişim',
  'gesundheit': 'Sağlık',
  'wohnen': 'Ev ve konut',
  'reisen': 'Seyahat',
  'freizeit': 'Boş zaman',
  'familie': 'Aile',
  'kleidung': 'Giyim',
  'wetter': 'Hava durumu',
  'natur': 'Doğa',
  'gefuehle': 'Duygular',
  'medien': 'Medya ve teknoloji',
};
