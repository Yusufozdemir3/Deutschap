import '../../../learning/text/lexicon.dart';
import '../../vocabulary/data/vocab_repository.dart';
import '../../vocabulary/domain/vocab_entry.dart';
import '../domain/word_pack.dart';

/// Result of importing a pack into the learner's library.
class PackImport {
  const PackImport({required this.collectionId, required this.added, required this.alreadySaved, required this.unknown});
  final String collectionId;
  final int added;
  final int alreadySaved;

  /// Word ids this app version does not know (newer content).
  final int unknown;
}

/// A collection as a shareable pack: dictionary words by id, the
/// learner's own words as text. Sentences stay private.
WordPack packFromEntries(String name, List<VocabEntry> entries, {String? note, bool teacher = false}) => WordPack(
      name: name,
      note: note,
      teacher: teacher,
      lexemeIds: [for (final e in entries) ?e.lexemeId],
      custom: [
        for (final e in entries)
          if (e.lexemeId == null && e.kind != 'sentence') CustomWord(headword: e.headword, meaningTr: e.meaningTr),
      ],
    );

/// Saves every word of [pack] and gathers them in a new collection.
Future<PackImport> importPack(WordPack pack, {required VocabRepository repo, required Lexicon lexicon}) async {
  final collectionId = await repo.createCollection(pack.name);
  var added = 0, already = 0, unknown = 0;
  for (final id in pack.lexemeIds) {
    final l = lexicon.byId(id);
    if (l == null) {
      unknown++;
      continue;
    }
    final (entry, existed) = await repo.saveLexeme(l);
    existed ? already++ : added++;
    await repo.setInCollection(collectionId, entry.id, true);
  }
  for (final c in pack.custom) {
    // Own words are matched by their text, so importing twice adds nothing.
    final same = (await repo.list(VocabQuery(text: c.headword, limit: 20))).where((e) => e.lexemeId == null && e.headword == c.headword).firstOrNull;
    if (same != null) {
      already++;
      await repo.setInCollection(collectionId, same.id, true);
      continue;
    }
    final m = RegExp(r'^(der|die|das) (.+)$').firstMatch(c.headword);
    final entry = await repo.saveManual(
      headword: c.headword,
      meaningTr: c.meaningTr,
      kind: m != null ? 'noun' : 'expression',
      article: m?.group(1),
      context: c.example == null || c.example!.isEmpty
          ? null
          : SourceContext(type: SourceType.manual, sourceId: 'pack', title: pack.name, sentence: c.example!),
    );
    added++;
    await repo.setInCollection(collectionId, entry.id, true);
  }
  return PackImport(collectionId: collectionId, added: added, alreadySaved: already, unknown: unknown);
}
