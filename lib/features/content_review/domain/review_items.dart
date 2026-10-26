import '../../../content/content_bundle.dart';
import '../../../content/models/lesson.dart';
import '../../../content/models/story.dart';

/// One piece of German (with its Turkish) that a human reviewer can
/// confirm or flag. Ids are stable across app versions as long as the
/// content ids do not change, so a reviewer's marks survive updates.
class ReviewItem {
  const ReviewItem({required this.id, required this.area, required this.where, required this.de, this.tr, this.extra});
  final String id;
  final ReviewArea area;

  /// Human-readable location, e.g. "A2 · Ders 3 · adım 4".
  final String where;
  final String de;
  final String? tr;

  /// Accepted answers, options or an explanation that belongs to the item.
  final String? extra;
}

enum ReviewArea {
  lexicon('Kelimeler'),
  lessons('Dersler'),
  stories('Hikâyeler'),
  reading('Okuma'),
  listening('Dinleme'),
  scenarios('Konuşmalar');

  const ReviewArea(this.labelTr);
  final String labelTr;
}

/// Every reviewable sentence in the bundle, in reading order.
List<ReviewItem> collectReviewItems(ContentBundle c) {
  final out = <ReviewItem>[];
  void add(ReviewArea area, String id, String where, String de, [String? tr, String? extra]) {
    if (de.trim().isEmpty) return;
    out.add(ReviewItem(id: id, area: area, where: where, de: de, tr: tr, extra: extra));
  }

  for (final l in c.lexicon.all) {
    add(ReviewArea.lexicon, 'lex:${l.id}', '${l.cefr} · ${l.pos.labelTr}', l.plural == null ? l.headword : '${l.headword}, die ${l.plural}', l.tr, l.noteTr);
    for (var i = 0; i < l.examples.length; i++) {
      add(ReviewArea.lexicon, 'lex:${l.id}:ex$i', '${l.headword} · örnek ${i + 1}', l.examples[i].de, l.examples[i].tr);
    }
  }

  void lesson(Lesson l, String where) {
    for (var i = 0; i < l.steps.length; i++) {
      final s = l.steps[i];
      final w = '$where · ${l.titleTr} · adım ${i + 1}';
      final id = 'step:${s.id}';
      switch (s) {
        case DialogueStep():
          for (var k = 0; k < s.lines.length; k++) {
            add(ReviewArea.lessons, '$id:$k', '$w · ${s.lines[k].speaker}', s.lines[k].de, s.lines[k].tr);
          }
        case ClozeStep():
          add(ReviewArea.lessons, id, w, s.de, s.tr, 'Cevap: ${s.answers.join(' / ')}');
        case OrderStep():
          add(ReviewArea.lessons, id, w, s.answers.first, s.tr, s.answers.length > 1 ? 'Diğer doğru sıralar: ${s.answers.skip(1).join(' / ')}' : null);
        case TranslateStep():
          add(ReviewArea.lessons, id, w, s.answers.join(' / '), s.tr, s.explainTr);
        case ChoiceStep():
          add(ReviewArea.lessons, id, w, s.de ?? s.options.join(' / '), s.promptTr, 'Doğru: ${[for (final a in s.answers) s.options[a]].join(' / ')}');
        case ListenStep():
          add(ReviewArea.lessons, id, w, s.de, s.promptTr, 'Doğru: ${[for (final a in s.answers) s.options[a]].join(' / ')}');
        case WriteStep():
          add(ReviewArea.lessons, id, w, s.model, s.promptTr);
        case TipStep():
          if (s.right != null) add(ReviewArea.lessons, id, w, s.right!, s.titleTr, s.wrong == null ? null : 'Yanlış örnek: ${s.wrong}');
          for (var k = 0; k < s.examples.length; k++) {
            add(ReviewArea.lessons, '$id:$k', w, s.examples[k].de, s.examples[k].tr);
          }
        case MatchStep():
          for (var k = 0; k < s.pairs.length; k++) {
            add(ReviewArea.lessons, '$id:$k', w, s.pairs[k].de, s.pairs[k].tr);
          }
        case IntroStep() || GrammarStep() || ArticleStep():
          break;
      }
    }
  }

  for (final p in c.paths) {
    for (final u in p.units) {
      for (final l in u.lessons) {
        lesson(l, '${p.level} · Ünite ${u.number}');
      }
    }
  }
  for (final l in c.traps) {
    lesson(l, 'Tuzaklar');
  }

  for (final s in c.stories) {
    for (final e in s.episodes) {
      final w = '${s.title} · ${e.number}. bölüm (${e.level})';
      for (final n in e.nodes.values) {
        switch (n) {
          case NarrationNode():
            add(ReviewArea.stories, 'ep:${e.id}:${n.id}', w, n.de, n.tr);
          case LineNode():
            add(ReviewArea.stories, 'ep:${e.id}:${n.id}', '$w · ${n.speaker}', n.de, n.tr);
          case ChoiceNode():
            for (final ch in n.choices) {
              add(ReviewArea.stories, 'ep:${e.id}:${n.id}:${ch.id}', '$w · seçenek (${ch.verdict.name})', ch.de, ch.tr, ch.feedbackTr);
            }
          case BranchNode() || EndNode():
            break;
        }
      }
      for (final g in e.grammar) {
        add(ReviewArea.stories, 'ep:${e.id}:g:${g.titleTr}', '$w · dilbilgisi', g.exampleDe, g.titleTr, g.bodyTr);
      }
    }
  }

  for (final r in c.readings) {
    for (var i = 0; i < r.paragraphs.length; i++) {
      add(ReviewArea.reading, 'read:${r.id}:$i', '${r.level} · ${r.title} · paragraf ${i + 1}', r.paragraphs[i].de, r.paragraphs[i].tr);
    }
  }
  for (final t in c.listening) {
    for (var i = 0; i < t.lines.length; i++) {
      add(ReviewArea.listening, 'listen:${t.id}:$i', '${t.level} · ${t.title} · ${t.lines[i].speaker}', t.lines[i].de, t.lines[i].tr);
    }
  }

  for (final s in c.scenarios) {
    final w = '${s.level} · ${s.titleTr}';
    add(ReviewArea.scenarios, 'sc:${s.id}:open', '$w · açılış', s.opening.de, s.opening.tr);
    for (final g in s.goals) {
      for (var i = 0; i < g.hints.length; i++) {
        add(ReviewArea.scenarios, 'sc:${s.id}:${g.id}:h$i', '$w · ipucu: ${g.labelTr}', g.hints[i].de, g.hints[i].tr);
      }
    }
    for (final it in s.intents) {
      for (var i = 0; i < it.matches.length; i++) {
        add(ReviewArea.scenarios, 'sc:${s.id}:${it.id}:$i', '$w · ${s.partnerName}', it.matches[i].reply.de, it.matches[i].reply.tr);
      }
      if (it.blocked != null) add(ReviewArea.scenarios, 'sc:${s.id}:${it.id}:blocked', '$w · ${s.partnerName}', it.blocked!.de, it.blocked!.tr);
    }
    for (var i = 0; i < s.fallback.length; i++) {
      add(ReviewArea.scenarios, 'sc:${s.id}:fb$i', '$w · anlaşılmadı', s.fallback[i].de, s.fallback[i].tr);
    }
    add(ReviewArea.scenarios, 'sc:${s.id}:close', '$w · kapanış', s.closing.de, s.closing.tr);
  }
  return out;
}

enum ReviewVerdict { ok, issue }

class ReviewMark {
  const ReviewMark(this.verdict, {this.note});
  final ReviewVerdict verdict;
  final String? note;

  Map<String, Object?> toJson() => {'v': verdict.name, if (note != null && note!.isNotEmpty) 'n': note};
  factory ReviewMark.fromJson(Map<String, dynamic> j) =>
      ReviewMark(ReviewVerdict.values.asNameMap()[j['v']] ?? ReviewVerdict.issue, note: j['n'] as String?);
}

/// Flagged items as tab-separated text for a spreadsheet or an issue.
String reviewReportTsv(List<ReviewItem> items, Map<String, ReviewMark> marks, {bool onlyIssues = true}) {
  String clean(String? v) => (v ?? '').replaceAll(RegExp(r'[\t\n]'), ' ');
  final b = StringBuffer('id\tarea\twhere\tde\ttr\tverdict\tnote\n');
  for (final i in items) {
    final m = marks[i.id];
    if (m == null || (onlyIssues && m.verdict != ReviewVerdict.issue)) continue;
    b.writeln([i.id, i.area.name, i.where, i.de, i.tr, m.verdict.name, m.note].map(clean).join('\t'));
  }
  return b.toString();
}
