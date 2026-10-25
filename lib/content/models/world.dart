import '../json_utils.dart';

/// Something that unlocks a place: completing a lesson, an episode number
/// (any level variant), a scenario, or a reading text.
class UnlockRef {
  const UnlockRef(this.kind, this.id);
  final String kind;
  final String id;

  static const kinds = {'lesson', 'episode', 'scenario', 'reading'};

  factory UnlockRef.parse(String s) {
    final i = s.indexOf(':');
    if (i <= 0) throw ContentFormatException('bad unlock "$s" (expected kind:id)');
    final kind = s.substring(0, i);
    if (!kinds.contains(kind)) throw ContentFormatException('unknown unlock kind "$kind"');
    return UnlockRef(kind, s.substring(i + 1));
  }

  @override
  String toString() => '$kind:$id';
}

/// A spot on the neighbourhood map. It lights up when the learner has
/// actually done something there (a lesson, an episode, a scenario).
class Place {
  const Place({
    required this.id,
    required this.nameDe,
    required this.nameTr,
    required this.icon,
    required this.x,
    required this.y,
    required this.aboutTr,
    required this.unlock,
    this.route,
  });

  final String id;
  final String nameDe;
  final String nameTr;
  final String icon;

  /// Position on the map, 0–1 in both directions.
  final double x;
  final double y;
  final String aboutTr;

  /// Any one of these unlocks the place.
  final List<UnlockRef> unlock;
  final String? route;

  factory Place.fromJson(Json j) => Place(
        id: j.str('id'),
        nameDe: j.str('name_de'),
        nameTr: j.str('name_tr'),
        icon: j.str('icon'),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        aboutTr: j.str('about_tr'),
        unlock: j.strList('unlock').map(UnlockRef.parse).toList(growable: false),
        route: j.optStr('route'),
      );
}

/// A clue on the mystery board. Revealed by finishing its episode;
/// "solved" once its words are recalled without help in review.
class Clue {
  const Clue({
    required this.id,
    required this.titleDe,
    required this.titleTr,
    required this.episode,
    required this.textTr,
    required this.quoteDe,
    required this.lexemes,
  });

  final String id;
  final String titleDe;
  final String titleTr;

  /// Episode number (any level variant) that reveals the clue.
  final int episode;
  final String textTr;
  final String quoteDe;
  final List<String> lexemes;

  factory Clue.fromJson(Json j) => Clue(
        id: j.str('id'),
        titleDe: j.str('title_de'),
        titleTr: j.str('title_tr'),
        episode: j.integer('episode'),
        textTr: j.str('text_tr'),
        quoteDe: j.str('quote_de'),
        lexemes: j.strList('lexemes'),
      );
}
