import 'dart:convert';

import 'package:flutter/services.dart';

import '../learning/text/lexicon.dart';
import 'json_utils.dart';
import 'models/discover.dart';
import 'models/grammar.dart';
import 'models/lesson.dart';
import 'models/lexeme.dart';
import 'models/reading.dart';
import 'models/scenario.dart';
import 'models/story.dart';
import 'models/world.dart';

/// All curated, read-only educational content shipped with the app.
/// Learner data never lives here.
class ContentBundle {
  ContentBundle({
    required this.version,
    required this.lexicon,
    required this.grammar,
    required this.paths,
    required this.stories,
    required this.readings,
    required this.scenarios,
    required this.discover,
    this.places = const [],
    this.clues = const [],
  }) {
    for (final u in paths.expand((p) => p.units)) {
      _units[u.id] = u;
      for (final l in u.lessons) {
        _lessons[l.id] = l;
        _unitOfLesson[l.id] = u;
      }
    }
    for (final s in stories) {
      for (final e in s.episodes) {
        _episodes[e.id] = e;
        _storyOfEpisode[e.id] = s;
      }
    }
  }

  static const files = [
    'lexicon.json',
    'grammar.json',
    'path_a1.json',
    'path_a2.json',
    'stories.json',
    'reading.json',
    'scenarios.json',
    'discover.json',
    'world.json',
  ];

  final String version;
  final Lexicon lexicon;
  final Map<String, GrammarConcept> grammar;
  /// Learning paths in level order (A1, A2, …).
  final List<LearningPath> paths;
  final List<Story> stories;
  final List<ReadingText> readings;
  final List<Scenario> scenarios;
  final List<DiscoverCard> discover;
  final List<Place> places;
  final List<Clue> clues;

  final _units = <String, Unit>{};
  final _lessons = <String, Lesson>{};
  final _unitOfLesson = <String, Unit>{};
  final _episodes = <String, Episode>{};
  final _storyOfEpisode = <String, Story>{};

  Iterable<Lesson> get lessons => _lessons.values;
  Lesson? lesson(String id) => _lessons[id];
  Unit? unit(String id) => _units[id];
  Iterable<Unit> get units => _units.values;

  LearningPath? pathFor(String level) => paths.where((p) => p.level == level).firstOrNull;
  Unit? unitOfLesson(String lessonId) => _unitOfLesson[lessonId];
  Episode? episode(String id) => _episodes[id];
  Story? storyOfEpisode(String episodeId) => _storyOfEpisode[episodeId];
  Iterable<Episode> get episodes => _episodes.values;

  Story? story(String id) {
    for (final s in stories) {
      if (s.id == id) return s;
    }
    return null;
  }

  Scenario? scenario(String id) {
    for (final s in scenarios) {
      if (s.id == id) return s;
    }
    return null;
  }

  ReadingText? reading(String id) {
    for (final r in readings) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Lessons in curriculum order.
  List<Lesson> get orderedLessons => [for (final p in paths) for (final u in p.units) ...u.lessons];

  /// The level of the path a lesson belongs to.
  String levelOfLesson(String lessonId) {
    for (final p in paths) {
      if (p.units.any((u) => u.lessons.any((l) => l.id == lessonId))) return p.level;
    }
    return 'A1';
  }

  /// Parses raw file contents keyed by file name. Throws
  /// [ContentFormatException] with the failing file and field.
  factory ContentBundle.fromSources(Map<String, String> sources) {
    Json read(String name) {
      final raw = sources[name];
      if (raw == null) throw ContentFormatException('missing content file $name');
      try {
        return (jsonDecode(raw) as Map).cast<String, dynamic>();
      } on FormatException catch (e) {
        throw ContentFormatException('$name is not valid JSON: ${e.message}');
      }
    }

    T guard<T>(String name, T Function(Json j) parse) {
      try {
        return parse(read(name));
      } on ContentFormatException catch (e) {
        throw ContentFormatException('$name: ${e.message}');
      } on TypeError catch (e) {
        throw ContentFormatException('$name: wrong type ($e)');
      }
    }

    final lexicon = guard('lexicon.json', (j) => Lexicon(j.objList('lexemes').map(Lexeme.fromJson)));
    return ContentBundle(
      version: guard('lexicon.json', (j) => j.str('version')),
      lexicon: lexicon,
      grammar: guard('grammar.json', (j) => {
            for (final g in j.objList('concepts').map(GrammarConcept.fromJson)) g.id: g,
          }),
      paths: [for (final f in files.where((f) => f.startsWith('path_'))) guard(f, LearningPath.fromJson)],
      stories: guard('stories.json', (j) => j.objList('stories').map(Story.fromJson).toList(growable: false)),
      readings: guard('reading.json', (j) => j.objList('texts').map(ReadingText.fromJson).toList(growable: false)),
      scenarios: guard('scenarios.json', (j) => j.objList('scenarios').map(Scenario.fromJson).toList(growable: false)),
      discover: guard('discover.json', (j) => j.objList('cards').map(DiscoverCard.fromJson).toList(growable: false)),
      places: guard('world.json', (j) => j.objList('places').map(Place.fromJson).toList(growable: false)),
      clues: guard('world.json', (j) => j.objList('clues').map(Clue.fromJson).toList(growable: false)),
    );
  }

  static Future<ContentBundle> load(AssetBundle assets) async {
    final sources = <String, String>{
      for (final f in files) f: await assets.loadString('assets/content/$f'),
    };
    return ContentBundle.fromSources(sources);
  }
}
