import 'dart:convert';

import '../learning/text/tokenizer.dart';
import 'content_bundle.dart';
import 'models/lesson.dart';
import 'models/lexeme.dart';
import 'models/story.dart';
import 'models/world.dart';

/// Automated checks every content change must pass (see
/// docs/CONTENT_REVIEW.md). They catch structural and many linguistic
/// data errors; they do not replace review by a qualified teacher.
class ContentValidator {
  ContentValidator(this.bundle, this.sources);
  final ContentBundle bundle;
  final Map<String, String> sources;

  final problems = <String>[];

  void _fail(String where, String msg) => problems.add('$where: $msg');

  List<String> validate() {
    problems.clear();
    _lexicon();
    _grammar();
    _path();
    _stories();
    _scenarios();
    _discover();
    _readings();
    _world();
    return problems;
  }

  bool _lex(String id) => bundle.lexicon.contains(id);

  void _lexicon() {
    final raw = (jsonDecode(sources['lexicon.json']!) as Map)['lexemes'] as List;
    final seen = <String>{};
    for (final r in raw) {
      final id = (r as Map)['id'] as String;
      if (!seen.add(id)) _fail('lexicon', 'duplicate id "$id"');
    }
    for (final l in bundle.lexicon.all) {
      final w = 'lexeme ${l.id}';
      if (l.lemma.trim().isEmpty || l.tr.trim().isEmpty) _fail(w, 'empty lemma or meaning');
      if (!RegExp(r'^(A1|A2|B1|B2|C1)$').hasMatch(l.cefr)) _fail(w, 'invalid CEFR "${l.cefr}"');
      if (l.isNoun) {
        final proper = l.tags.contains('proper');
        if (!proper && !const {'der', 'die', 'das'}.contains(l.article)) _fail(w, 'noun without valid article');
        if (l.article != null && !const {'der', 'die', 'das'}.contains(l.article)) _fail(w, 'invalid article "${l.article}"');
        if (l.plural == null) {
          _fail(w, 'noun needs a plural ("die …" or "—")');
        } else if (l.plural != '—' && !l.plural!.startsWith('die ')) {
          _fail(w, 'plural must start with "die ": ${l.plural}');
        }
        if (l.lemma[0] != l.lemma[0].toUpperCase()) _fail(w, 'noun lemma must be capitalised');
      } else if (l.article != null) {
        _fail(w, 'only nouns have an article');
      }
      if (l.pos == PartOfSpeech.verb) {
        final v = l.verb;
        if (v == null) {
          _fail(w, 'verb without verb info');
        } else {
          if (!const {'haben', 'sein'}.contains(v.auxiliary)) _fail(w, 'aux must be haben or sein');
          if (v.participle.isEmpty) _fail(w, 'missing participle');
        }
      }
      for (final e in l.examples) {
        if (e.de.trim().isEmpty || e.tr.trim().isEmpty) _fail(w, 'empty example');
      }
      for (final r in l.related) {
        if (!_lex(r)) _fail(w, 'related "$r" not found');
      }
    }
  }

  void _grammar() {
    for (final g in bundle.grammar.values) {
      for (final r in g.requires) {
        if (!bundle.grammar.containsKey(r)) _fail('grammar ${g.id}', 'requires unknown "$r"');
      }
      if (g.table.isNotEmpty) {
        final width = g.table.first.length;
        for (final row in g.table) {
          if (row.length != width) _fail('grammar ${g.id}', 'table rows have different widths');
        }
      }
    }
    // Prerequisites must not form a cycle.
    final state = <String, int>{};
    bool visit(String id) {
      if (state[id] == 1) return false;
      if (state[id] == 2) return true;
      state[id] = 1;
      for (final r in bundle.grammar[id]?.requires ?? const <String>[]) {
        if (!visit(r)) return false;
      }
      state[id] = 2;
      return true;
    }

    for (final id in bundle.grammar.keys) {
      if (!visit(id)) _fail('grammar $id', 'prerequisite cycle');
    }
  }

  void _path() {
    final lessonIds = <String>{};
    for (final l in bundle.traps) {
      if (!lessonIds.add(l.id)) _fail('lesson ${l.id}', 'duplicate id');
      if (l.gradedStepCount == 0) _fail('lesson ${l.id}', 'no graded step');
      for (final s in l.steps) {
        _step(l, s);
      }
    }
    final unitIds = <String>{};
    for (final u in bundle.paths.expand((p) => p.units)) {
      if (!unitIds.add(u.id)) _fail('unit ${u.id}', 'duplicate id');
      for (final g in u.grammar) {
        if (!bundle.grammar.containsKey(g)) _fail('unit ${u.id}', 'grammar "$g" not found');
      }
      for (final l in u.lessons) {
        if (!lessonIds.add(l.id)) _fail('lesson ${l.id}', 'duplicate id');
        for (final v in l.vocab) {
          if (!_lex(v)) _fail('lesson ${l.id}', 'vocab "$v" not found');
        }
        if (l.gradedStepCount == 0) _fail('lesson ${l.id}', 'no graded step');
        for (final s in l.steps) {
          _step(l, s);
        }
      }
    }
  }

  void _step(Lesson l, LessonStep s) {
    final w = 'step ${s.id}';
    switch (s) {
      case IntroStep(:final lexemes):
        if (lexemes.isEmpty) _fail(w, 'intro without lexemes');
        for (final x in lexemes) {
          if (!_lex(x)) _fail(w, 'lexeme "$x" not found');
        }
      case GrammarStep(:final conceptId):
        if (!bundle.grammar.containsKey(conceptId)) _fail(w, 'concept "$conceptId" not found');
      case DialogueStep(:final lines):
        if (lines.length < 2) _fail(w, 'dialogue needs at least two lines');
      case ChoiceStep(:final options, :final answers):
        if (options.length < 2) _fail(w, 'needs at least two options');
        if (answers.isEmpty || answers.any((a) => a < 0 || a >= options.length)) _fail(w, 'answer index out of range');
        if (options.toSet().length != options.length) _fail(w, 'duplicate options');
      case ArticleStep(:final lexemeId):
        final lx = bundle.lexicon.byId(lexemeId);
        if (lx == null || !lx.isNoun || lx.article == null) _fail(w, '"$lexemeId" is not a noun with an article');
      case ClozeStep(:final de, :final answers, :final options):
        if ('___'.allMatches(de).length != 1) _fail(w, 'cloze needs exactly one "___"');
        if (answers.isEmpty) _fail(w, 'cloze without answers');
        if (options.isNotEmpty && !answers.any(options.contains)) _fail(w, 'no answer among options');
      case OrderStep(:final tokens, :final answers):
        final want = (words(tokens.join(' ')).map((t) => t.toLowerCase()).toList()..sort()).join('|');
        for (final a in answers) {
          final got = (words(a).map((t) => t.toLowerCase()).toList()..sort()).join('|');
          if (got != want) _fail(w, 'answer "$a" does not use exactly the tokens');
        }
      case TranslateStep(:final answers):
        if (answers.isEmpty) _fail(w, 'translate without answers');
      case ListenStep(:final options, :final answers):
        if (options.length < 2 || answers.isEmpty || answers.any((a) => a < 0 || a >= options.length)) _fail(w, 'listen answers out of range');
      case TipStep(:final bodyTr):
        if (bodyTr.trim().isEmpty) _fail(w, 'tip without text');
      case MatchStep(:final pairs):
        if (pairs.length < 3) _fail(w, 'match needs at least three pairs');
        if (pairs.map((x) => x.de).toSet().length != pairs.length || pairs.map((x) => x.tr).toSet().length != pairs.length) {
          _fail(w, 'match sides must be unique');
        }
      case WriteStep(:final requirements, :final model):
        if (requirements.isEmpty) _fail(w, 'write needs requirements');
        for (final r in requirements) {
          try {
            if (!RegExp(r.pattern).hasMatch(fold(model))) _fail(w, 'model answer misses requirement "${r.labelTr}"');
          } on FormatException {
            _fail(w, 'bad regex ${r.pattern}');
          }
        }
    }
  }

  void _stories() {
    final episodeIds = <String>{};
    for (final story in bundle.stories) {
      final chars = {for (final c in story.characters) c.id};
      for (final e in story.episodes) {
        final w = 'episode ${e.id}';
        if (!episodeIds.add(e.id)) _fail(w, 'duplicate id');
        if (!e.nodes.containsKey(e.start)) _fail(w, 'start node "${e.start}" missing');
        for (final v in e.vocab) {
          if (!_lex(v)) _fail(w, 'vocab "$v" not found');
        }
        if (e.scenarioId != null && bundle.scenario(e.scenarioId!) == null) _fail(w, 'scenario "${e.scenarioId}" not found');
        for (final q in e.quiz) {
          if (q.answer < 0 || q.answer >= q.options.length) _fail(w, 'quiz ${q.id} answer out of range');
        }
        for (final g in e.grammar) {
          if (g.conceptId != null && !bundle.grammar.containsKey(g.conceptId)) _fail(w, 'grammar concept "${g.conceptId}" not found');
        }
        _graph(e, chars, w);
      }
    }
  }

  void _graph(Episode e, Set<String> chars, String w) {
    final setFlags = <String>{};
    final edges = <String, List<String>>{};
    for (final n in e.nodes.values) {
      final targets = <String>[];
      switch (n) {
        case NarrationNode(:final next):
          targets.add(next);
        case LineNode(:final next, :final speaker):
          targets.add(next);
          if (!chars.contains(speaker)) _fail(w, 'node ${n.id}: unknown speaker "$speaker"');
        case ChoiceNode(:final choices):
          if (choices.length < 2) _fail(w, 'node ${n.id}: choice needs at least two options');
          if (!choices.any((c) => c.verdict == ChoiceVerdict.best)) _fail(w, 'node ${n.id}: no "best" choice');
          if (!choices.any((c) => c.next != null)) _fail(w, 'node ${n.id}: no choice continues the story');
          for (final c in choices) {
            setFlags.addAll(c.setFlags);
            if (c.verdict == ChoiceVerdict.wrong && c.next != null) _fail(w, 'node ${n.id}/${c.id}: wrong choices must not advance');
            if (c.verdict != ChoiceVerdict.wrong && c.next == null) _fail(w, 'node ${n.id}/${c.id}: accepted choice needs "next"');
            if (c.next != null) targets.add(c.next!);
            if (c.feedbackTr.trim().isEmpty) _fail(w, 'node ${n.id}/${c.id}: missing feedback');
          }
        case BranchNode(:final cases, :final otherwise):
          targets.addAll([...cases.map((c) => c.next), otherwise]);
        case EndNode():
          break;
      }
      for (final t in targets) {
        if (!e.nodes.containsKey(t)) _fail(w, 'node ${n.id} points to missing "$t"');
      }
      edges[n.id] = targets;
    }
    for (final n in e.nodes.values.whereType<BranchNode>()) {
      for (final c in n.cases) {
        if (!setFlags.contains(c.flag)) _fail(w, 'branch ${n.id}: flag "${c.flag}" is never set');
      }
    }
    // Reachability from start and termination at an end node.
    final reached = <String>{};
    final stack = [e.start];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      if (!reached.add(id)) continue;
      stack.addAll((edges[id] ?? const []).where(e.nodes.containsKey));
    }
    for (final id in e.nodes.keys) {
      if (!reached.contains(id)) _fail(w, 'node $id is unreachable');
    }
    if (!e.nodes.values.any((n) => n is EndNode)) _fail(w, 'no end node');
    final canEnd = <String>{for (final n in e.nodes.values) if (n is EndNode) n.id};
    var changed = true;
    while (changed) {
      changed = false;
      for (final entry in edges.entries) {
        if (!canEnd.contains(entry.key) && entry.value.any(canEnd.contains)) {
          canEnd.add(entry.key);
          changed = true;
        }
      }
    }
    for (final id in reached) {
      if (!canEnd.contains(id)) _fail(w, 'node $id cannot reach an end');
    }
  }

  void _scenarios() {
    final ids = <String>{};
    for (final s in bundle.scenarios) {
      final w = 'scenario ${s.id}';
      if (!ids.add(s.id)) _fail(w, 'duplicate id');
      final goals = {for (final g in s.goals) g.id};
      if (goals.length != s.goals.length) _fail(w, 'duplicate goal ids');
      if (s.fallback.isEmpty) _fail(w, 'no fallback reply');
      for (final g in s.goals) {
        if (g.hints.isEmpty) _fail(w, 'goal ${g.id} has no hints');
        if (!s.intents.any((i) => i.goal == g.id)) _fail(w, 'goal ${g.id} has no intent');
      }
      for (final i in s.intents) {
        if (i.goal != null && !goals.contains(i.goal)) _fail(w, 'intent ${i.id}: unknown goal "${i.goal}"');
        for (final r in i.requires) {
          if (!goals.contains(r)) _fail(w, 'intent ${i.id}: requires unknown goal "$r"');
        }
        for (final m in i.matches) {
          try {
            RegExp(m.pattern);
          } on FormatException catch (e) {
            _fail(w, 'intent ${i.id}: bad regex ${m.pattern} (${e.message})');
          }
        }
      }
      for (final v in s.vocab) {
        if (!_lex(v)) _fail(w, 'vocab "$v" not found');
      }
    }
  }

  void _discover() {
    final ids = <String>{};
    final bodies = <String>{};
    for (final c in bundle.discover) {
      final w = 'discover ${c.id}';
      if (!ids.add(c.id)) _fail(w, 'duplicate id');
      if (!bodies.add(c.bodyDe)) _fail(w, 'duplicate content');
      for (final l in c.lexemes) {
        if (!_lex(l)) _fail(w, 'lexeme "$l" not found');
      }
      if (c.question != null && (c.answer == null || c.answer! < 0 || c.answer! >= c.options.length)) {
        _fail(w, 'answer out of range');
      }
      if (c.objectiveTr.trim().isEmpty) _fail(w, 'missing learning objective');
    }
  }

  void _readings() {
    final ids = <String>{};
    for (final r in bundle.readings) {
      if (!ids.add(r.id)) _fail('reading ${r.id}', 'duplicate id');
      for (final q in r.questions) {
        if (q.answer < 0 || q.answer >= q.options.length) _fail('reading ${r.id}', 'answer out of range');
      }
    }
    final familyIds = <String>{};
    for (final f in bundle.families) {
      final w = 'family ${f.id}';
      if (!familyIds.add(f.id)) _fail(w, 'duplicate id');
      if (f.members.length < 2) _fail(w, 'needs at least two members');
      if (f.members.toSet().length != f.members.length) _fail(w, 'duplicate member');
      for (final m in f.members) {
        if (!_lex(m)) _fail(w, 'member "$m" not found');
      }
    }
    final trackIds = <String>{};
    for (final t in bundle.listening) {
      final w = 'listening ${t.id}';
      if (!trackIds.add(t.id)) _fail(w, 'duplicate id');
      if (t.lines.length < 2) _fail(w, 'needs at least two lines');
      if (t.questions.isEmpty) _fail(w, 'needs comprehension questions');
      for (final q in t.questions) {
        if (q.answer < 0 || q.answer >= q.options.length) _fail(w, 'answer out of range');
        if (q.options.toSet().length != q.options.length) _fail(w, 'duplicate options');
      }
    }
  }

  void _world() {
    final episodeNumbers = {for (final s in bundle.stories) ...s.episodeNumbers};
    bool exists(UnlockRef r) => switch (r.kind) {
          'lesson' => bundle.lesson(r.id) != null,
          'episode' => episodeNumbers.contains(int.tryParse(r.id)),
          'scenario' => bundle.scenario(r.id) != null,
          'reading' => bundle.reading(r.id) != null,
          'listening' => bundle.track(r.id) != null,
          _ => false,
        };
    final ids = <String>{};
    for (final p in bundle.places) {
      final w = 'place ${p.id}';
      if (!ids.add(p.id)) _fail(w, 'duplicate id');
      if (p.x < 0 || p.x > 1 || p.y < 0 || p.y > 1) _fail(w, 'position outside 0–1');
      if (p.unlock.isEmpty) _fail(w, 'no unlock condition');
      for (final u in p.unlock) {
        if (!exists(u)) _fail(w, 'unlock "$u" does not exist');
      }
    }
    final clueIds = <String>{};
    for (final c in bundle.clues) {
      final w = 'clue ${c.id}';
      if (!clueIds.add(c.id)) _fail(w, 'duplicate id');
      if (!episodeNumbers.contains(c.episode)) _fail(w, 'episode ${c.episode} does not exist');
      if (c.lexemes.isEmpty) _fail(w, 'needs lexemes');
      for (final l in c.lexemes) {
        if (!_lex(l)) _fail(w, 'lexeme "$l" not found');
      }
    }
  }
}
