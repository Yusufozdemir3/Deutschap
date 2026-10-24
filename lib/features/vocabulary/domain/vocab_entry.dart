import '../../review/domain/scheduler.dart';
import 'vocab_status.dart';

enum SourceType {
  story('Hikâye'),
  reading('Okuma'),
  lesson('Ders'),
  conversation('Konuşma'),
  discover('Keşfet'),
  manual('Elle eklendi');

  const SourceType(this.labelTr);
  final String labelTr;
}

/// Where a word was met. Preserved so review and recommendations can
/// refer back to the original sentence.
class SourceContext {
  const SourceContext({
    required this.type,
    this.sourceId = '',
    this.title,
    this.sentence = '',
    this.sentenceTr,
    this.createdAt,
  });

  final SourceType type;
  final String sourceId;
  final String? title;
  final String sentence;
  final String? sentenceTr;
  final DateTime? createdAt;

  /// Route back to the source, when it still exists.
  String? get route => switch (type) {
        SourceType.story when sourceId.isNotEmpty => '/episode/$sourceId',
        SourceType.reading when sourceId.isNotEmpty => '/reader/$sourceId',
        SourceType.lesson when sourceId.isNotEmpty => '/lesson/$sourceId',
        SourceType.conversation when sourceId.isNotEmpty => '/scenario/$sourceId',
        _ => null,
      };
}

class VocabEntry {
  const VocabEntry({
    required this.id,
    required this.headword,
    required this.lemma,
    required this.kind,
    required this.meaningTr,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.lexemeId,
    this.article,
    this.plural,
    this.meaningEn,
    this.note,
    this.paused = false,
  });

  final String id;

  /// Curated lexeme this entry was saved from; null for manual entries.
  final String? lexemeId;
  final String headword;
  final String lemma;

  /// PartOfSpeech name ("noun", "verb", "expression", …).
  final String kind;
  final String? article;
  final String? plural;
  final String meaningTr;
  final String? meaningEn;
  final String? note;
  final VocabStatus status;
  final bool paused;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isNoun => kind == 'noun';
}

class ReviewCard {
  const ReviewCard({required this.entryId, required this.type, required this.state});
  final String entryId;
  final CardType type;
  final CardState state;
}

/// A card scheduled for review, with what the UI needs to show it.
class DueItem {
  const DueItem({required this.entry, required this.card, this.context});
  final VocabEntry entry;
  final ReviewCard card;
  final SourceContext? context;
}

class ReviewOutcome {
  const ReviewOutcome({required this.state, required this.before, required this.after, required this.duplicate});
  final CardState state;
  final VocabStatus before;
  final VocabStatus after;

  /// True when the event id was already recorded (retry after a crash).
  final bool duplicate;
}

class CollectionInfo {
  const CollectionInfo({required this.id, required this.name, required this.count});
  final String id;
  final String name;
  final int count;
}
