import '../../../content/models/discover.dart';

/// Builds a finite discover session: unseen cards first, interests
/// preferred, hidden topics excluded, and one card from outside the
/// learner's interests so the feed does not narrow itself.
List<DiscoverCard> buildDiscoverSession({
  required List<DiscoverCard> all,
  required Map<String, int> lastSeen,
  required Set<String> interests,
  required Set<String> hiddenTopics,
  int size = 5,
}) {
  final pool = all.where((c) => !c.topics.any(hiddenTopics.contains)).toList();
  int score(DiscoverCard c) {
    final seen = lastSeen[c.id];
    final interest = interests.isEmpty || c.topics.any(interests.contains) ? 1 : 0;
    // Never-seen first, then least recently seen; interest breaks ties.
    return (seen == null ? 1 << 50 : -seen) + interest;
  }

  final ranked = [...pool]..sort((a, b) => score(b).compareTo(score(a)));
  final session = <DiscoverCard>[];
  final kinds = <DiscoverKind, int>{};
  for (final c in ranked) {
    if (session.length >= size) break;
    // Variety: at most two cards of the same kind per session.
    if ((kinds[c.kind] ?? 0) >= 2) continue;
    session.add(c);
    kinds[c.kind] = (kinds[c.kind] ?? 0) + 1;
  }
  if (interests.isNotEmpty && session.isNotEmpty && session.every((c) => c.topics.any(interests.contains))) {
    final outside = ranked.where((c) => !c.topics.any(interests.contains) && !session.contains(c)).firstOrNull;
    if (outside != null) session[session.length - 1] = outside;
  }
  return session;
}
