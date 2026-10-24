import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../content/models/lexeme.dart';
import '../data/vocab_repository.dart';
import '../domain/vocab_entry.dart';

/// Lower-case surface forms of every saved single-word lexeme, used to
/// mark known words in texts.
final knownSurfacesProvider = Provider<Set<String>>((ref) {
  final saved = ref.watch(savedLexemeIdsProvider).valueOrNull ?? const <String>{};
  final lexicon = ref.watch(contentProvider).lexicon;
  final out = <String>{};
  for (final id in saved) {
    final l = lexicon.byId(id);
    if (l == null || l.isMultiWord) continue;
    out.add(l.lemma.toLowerCase());
    for (final f in l.forms) {
      out.add(f.toLowerCase());
    }
  }
  return out;
});

final vocabQueryProvider = StateProvider<VocabQuery>((ref) => const VocabQuery(limit: 200));

final vocabListProvider = FutureProvider<List<VocabEntry>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(vocabRepositoryProvider).list(ref.watch(vocabQueryProvider));
});

final vocabCountProvider = FutureProvider<int>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(vocabRepositoryProvider).count();
});

final collectionsProvider = FutureProvider<List<CollectionInfo>>((ref) {
  ref.watch(dataRevisionProvider);
  return ref.watch(vocabRepositoryProvider).collections();
});

class EntryDetails {
  const EntryDetails({required this.entry, required this.contexts, required this.cards, required this.collections, this.lexeme});
  final VocabEntry entry;
  final Lexeme? lexeme;
  final List<SourceContext> contexts;
  final List<ReviewCard> cards;
  final Set<String> collections;
}

final entryDetailsProvider = FutureProvider.family<EntryDetails?, String>((ref, id) async {
  ref.watch(dataRevisionProvider);
  final repo = ref.watch(vocabRepositoryProvider);
  final e = await repo.entry(id);
  if (e == null) return null;
  return EntryDetails(
    entry: e,
    lexeme: e.lexemeId == null ? null : ref.watch(contentProvider).lexicon.byId(e.lexemeId!),
    contexts: await repo.contexts(id),
    cards: await repo.cards(id),
    collections: await repo.collectionsOf(id),
  );
});

/// Saves a lexeme with its context and refreshes dependent screens.
Future<VocabEntry> saveLexeme(WidgetRef ref, Lexeme l, SourceContext? context) async {
  final (entry, _) = await ref.read(vocabRepositoryProvider).saveLexeme(l, context: context);
  ref.bumpData();
  return entry;
}
