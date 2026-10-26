import 'dart:convert';

import 'package:deutschap/core/db/app_database.dart';
import 'package:deutschap/features/conversation/domain/language_issue.dart';
import 'package:deutschap/features/drill/application/drill_words.dart';
import 'package:deutschap/features/drill/domain/vocab_drill.dart';
import 'package:deutschap/features/home/domain/recommender.dart';
import 'package:deutschap/features/sharing/application/pack_service.dart';
import 'package:deutschap/features/sharing/domain/word_pack.dart';
import 'package:deutschap/features/profile/data/profile_repository.dart';
import 'package:deutschap/features/profile/domain/learner_profile.dart';
import 'package:deutschap/features/progress/data/progress_repository.dart';
import 'package:deutschap/features/progress/data/stats_repository.dart';
import 'package:deutschap/features/reading/data/reading_repository.dart';
import 'package:deutschap/features/review/domain/scheduler.dart';
import 'package:deutschap/features/settings/data/data_repository.dart';
import 'package:deutschap/features/stories/domain/story_runner.dart';
import 'package:deutschap/features/vocabulary/data/vocab_repository.dart';
import 'package:deutschap/features/vocabulary/domain/vocab_entry.dart';
import 'package:deutschap/features/vocabulary/domain/vocab_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';
import '../helpers/test_db.dart';

void main() {
  final content = loadTestContent();
  late TestDb testDb;
  late AppDatabase db;
  late FakeClock clock;
  late SeqIds ids;
  late VocabRepository vocab;

  setUp(() async {
    testDb = await TestDb.create();
    db = await testDb.open();
    clock = FakeClock(DateTime(2026, 3, 2, 9));
    ids = SeqIds();
    vocab = VocabRepository(db.db, clock: clock.call, ids: ids.call);
  });

  tearDown(() async {
    await db.close();
    await testDb.dispose();
  });

  const storyContext = SourceContext(
    type: SourceType.story,
    sourceId: 'nib_e3_a1',
    title: 'Der Termin',
    sentence: 'Ich möchte einen Termin vereinbaren.',
    sentenceTr: 'Bir randevu almak istiyorum.',
  );

  group('VocabRepository', () {
    test('saving a noun creates recognition and article cards and keeps the context', () async {
      final (entry, existed) = await vocab.saveLexeme(content.lexicon.byId('termin')!, context: storyContext);
      expect(existed, isFalse);
      expect(entry.headword, 'der Termin');
      expect(entry.plural, 'die Termine');
      expect(entry.status, VocabStatus.newlyEncountered);
      final cards = await vocab.cards(entry.id);
      expect(cards.map((c) => c.type).toSet(), {CardType.recognition, CardType.article});
      final ctx = await vocab.contexts(entry.id);
      expect(ctx.single.sentence, storyContext.sentence);
      expect(ctx.single.route, '/episode/nib_e3_a1');
    });

    test('saving twice adds a new context instead of a duplicate entry', () async {
      final l = content.lexicon.byId('termin')!;
      await vocab.saveLexeme(l, context: storyContext);
      final (again, existed) = await vocab.saveLexeme(l,
          context: const SourceContext(type: SourceType.reading, sourceId: 'r1', sentence: 'Ich habe morgen einen Termin.'));
      await vocab.saveLexeme(l, context: storyContext); // identical context ignored
      expect(existed, isTrue);
      expect(await vocab.count(), 1);
      expect((await vocab.contexts(again.id)).length, 2);
    });

    test('expressions get no article card; proper nouns neither', () async {
      final (e, _) = await vocab.saveLexeme(content.lexicon.byId('termin_vereinbaren')!);
      expect((await vocab.cards(e.id)).map((c) => c.type), [CardType.recognition]);
      final (t, _) = await vocab.saveLexeme(content.lexicon.byId('tuerkei')!);
      expect((await vocab.cards(t.id)).map((c) => c.type), [CardType.recognition]);
    });

    test('review events are idempotent', () async {
      final (e, _) = await vocab.saveLexeme(content.lexicon.byId('kaffee')!);
      final first = await vocab.recordReview(eventId: 'ev1', entryId: e.id, type: CardType.recognition, grade: Grade.good, assisted: false);
      final replay = await vocab.recordReview(eventId: 'ev1', entryId: e.id, type: CardType.recognition, grade: Grade.good, assisted: false);
      expect(first.duplicate, isFalse);
      expect(replay.duplicate, isTrue);
      final events = await db.db.query('review_events');
      expect(events.length, 1);
      final card = (await vocab.cards(e.id)).firstWhere((c) => c.type == CardType.recognition);
      expect(card.state.reps, 1);
    });

    test('unaided recognition unlocks a production card; assisted does not', () async {
      final (a, _) = await vocab.saveLexeme(content.lexicon.byId('tee')!);
      final (b, _) = await vocab.saveLexeme(content.lexicon.byId('wasser')!);
      await vocab.recordReview(eventId: 'a', entryId: a.id, type: CardType.recognition, grade: Grade.good, assisted: false);
      await vocab.recordReview(eventId: 'b', entryId: b.id, type: CardType.recognition, grade: Grade.good, assisted: true);
      expect((await vocab.cards(a.id)).map((c) => c.type), contains(CardType.production));
      expect((await vocab.cards(b.id)).map((c) => c.type), isNot(contains(CardType.production)));
    });

    test('status moves from new to learning, never to mastered after one answer', () async {
      final (e, _) = await vocab.saveLexeme(content.lexicon.byId('brezel')!);
      final out = await vocab.recordReview(eventId: 'x', entryId: e.id, type: CardType.recognition, grade: Grade.easy, assisted: false);
      expect(out.before, VocabStatus.newlyEncountered);
      expect(out.after, VocabStatus.learning);
    });

    test('due items respect time and paused entries', () async {
      final (e, _) = await vocab.saveLexeme(content.lexicon.byId('brot')!);
      expect(await vocab.dueCount(), 2); // recognition + article
      expect((await vocab.dueItems()).length, 1, reason: 'one card per entry per session');
      await vocab.setPaused(e.id, true);
      expect(await vocab.dueCount(), 0);
      expect((await vocab.entry(e.id))!.status, VocabStatus.savedForLater);
      await vocab.setPaused(e.id, false);
      await vocab.recordReview(eventId: '1', entryId: e.id, type: CardType.recognition, grade: Grade.good, assisted: false);
      await vocab.recordReview(eventId: '2', entryId: e.id, type: CardType.article, grade: Grade.good, assisted: false);
      expect(await vocab.dueCount(), 0);
      clock.advance(const Duration(days: 2));
      expect(await vocab.dueCount(), greaterThan(0));
    });

    test('search, filter and collections', () async {
      final (k, _) = await vocab.saveLexeme(content.lexicon.byId('kaffee')!);
      await vocab.saveLexeme(content.lexicon.byId('tee')!);
      await vocab.saveManual(headword: 'die Kastanie', meaningTr: 'kestane', kind: 'noun', article: 'die', plural: 'die Kastanien');
      expect((await vocab.list(const VocabQuery(text: 'kahve'))).single.id, k.id);
      expect((await vocab.list(const VocabQuery(kind: 'noun'))).length, 3);
      final col = await vocab.createCollection('Kafe');
      await vocab.setInCollection(col, k.id, true);
      expect((await vocab.list(VocabQuery(collectionId: col))).single.id, k.id);
      expect(await vocab.collectionLexemeIds(col), ['kaffee']);
      expect((await vocab.collections()).single.count, 1);
      await vocab.delete(k.id);
      expect((await vocab.collections()).single.count, 0, reason: 'membership cascades');
    });

    test('manual entries store article and lemma separately', () async {
      final e = await vocab.saveManual(headword: 'die Kastanie', meaningTr: 'kestane', kind: 'noun', article: 'die');
      expect(e.lemma, 'Kastanie');
      expect((await vocab.cards(e.id)).map((c) => c.type).toSet(), {CardType.recognition, CardType.article});
    });
  });

  group('ProgressRepository', () {
    late ProgressRepository progress;
    setUp(() => progress = ProgressRepository(db.db, clock: clock.call, ids: ids.call));

    test('lesson position survives and completion is kept on replay', () async {
      await progress.saveLessonStep('u1l1', stepIndex: 3, correct: 2, total: 3);
      expect((await progress.lesson('u1l1'))!.stepIndex, 3);
      await progress.completeLesson('u1l1', correct: 6, total: 7);
      final done = await progress.lesson('u1l1');
      expect(done!.status, LessonStatus.completed);
      await progress.saveLessonStep('u1l1', stepIndex: 1, correct: 0, total: 1);
      expect((await progress.lesson('u1l1'))!.status, LessonStatus.completed);
    });

    test('episode state round-trips and completion is logged once', () async {
      const s = StoryState(nodeId: 'n6', flags: {'formell'}, history: [StoryStep('n1'), StoryStep('n4', choiceId: 'b', wrongChoiceIds: ['c'])]);
      await progress.saveEpisodeState('nib_e1_a1', 'neu_in_berlin', s);
      final p = (await progress.episode('nib_e1_a1'))!;
      expect(p.nodeId, 'n6');
      expect(p.flags, {'formell'});
      expect(p.history[1].wrongChoiceIds, ['c']);
      await progress.completeEpisode('nib_e1_a1', quizCorrect: 3, quizTotal: 3);
      await progress.completeEpisode('nib_e1_a1', quizCorrect: 2, quizTotal: 3);
      final log = await progress.recentActivity();
      expect(log.where((a) => a.kind == ActivityKind.story).length, 1);
    });

    test('conversation corrections feed recurring issues; history can be deleted', () async {
      const issue = LanguageIssue(kind: IssueKind.grammar, severity: IssueSeverity.error, original: 'x', corrected: 'y', explanationTr: 'z', ruleId: 'perfekt_sein');
      await progress.saveConversation(id: 'c1', scenarioId: 'cafe', mode: 'practice', completed: true, goalsDone: ['bestellen'], corrections: [issue, issue]);
      expect((await progress.recurringIssues())['perfekt_sein'], 2);
      expect(await progress.completedScenarioIds(), {'cafe'});
      await progress.deleteConversationHistory();
      expect(await progress.recurringIssues(), isEmpty);
    });

    test('active days include reviews and activities', () async {
      await progress.logActivity(ActivityKind.reading, refId: 'r1');
      clock.advance(const Duration(days: 1));
      final (e, _) = await vocab.saveLexeme(content.lexicon.byId('tee')!);
      await vocab.recordReview(eventId: 'r', entryId: e.id, type: CardType.recognition, grade: Grade.good, assisted: false);
      final days = await progress.activeDays(DateTime(2026, 3, 1));
      expect(days.length, 2);
    });
  });

  group('Stats, profile, reading, data', () {
    test('stats count unaided and assisted recalls separately', () async {
      final stats = StatsRepository(db.db, clock: clock.call);
      final (a, _) = await vocab.saveLexeme(content.lexicon.byId('tee')!);
      final (b, _) = await vocab.saveLexeme(content.lexicon.byId('kaffee')!);
      await vocab.recordReview(eventId: '1', entryId: a.id, type: CardType.recognition, grade: Grade.good, assisted: false);
      await vocab.recordReview(eventId: '2', entryId: b.id, type: CardType.recognition, grade: Grade.good, assisted: true);
      final s = await stats.load();
      expect(s.unaidedRecallsThisWeek, 1);
      expect(s.assistedRecallsThisWeek, 1);
      expect(s.delayedRetention, isNull, reason: 'no delayed reviews yet: do not invent a rate');
      expect(s.weeklyUnaided.length, 6);
      expect(s.weeklyUnaided.last, 1);
    });

    test('profile persists', () async {
      final repo = ProfileRepository(db.db, clock: clock.call);
      expect((await repo.load()).onboarded, isFalse);
      await repo.save(const LearnerProfile(onboarded: true, name: 'Deniz', interests: {'essen'}, motivation: Motivation.moving));
      final p = await repo.load();
      expect((p.onboarded, p.name, p.motivation), (true, 'Deniz', Motivation.moving));
      expect(p.interests, {'essen'});
    });

    test('reading docs: pasted text, position, deletion', () async {
      final repo = ReadingRepository(db.db, clock: clock.call, ids: ids.call);
      final id = await repo.addPasted('', 'Das ist ein Test. Noch ein Satz.');
      expect((await repo.doc(id))!.title, 'Das ist ein Test');
      await repo.savePosition(id, 1);
      expect((await repo.doc(id))!.position, 1);
      await repo.delete(id);
      expect(await repo.doc(id), isNull);
      expect(() => repo.addPasted('x', '   '), throwsArgumentError);
      final b = await repo.openBuiltin('r_mein_zimmer', 'Mein Zimmer', 'Text');
      final again = await repo.openBuiltin('r_mein_zimmer', 'Mein Zimmer', 'Text');
      expect(b.id, again.id);
    });

    test('export contains learner data; delete removes everything', () async {
      final data = DataRepository(db.db, clock: clock.call);
      await vocab.saveLexeme(content.lexicon.byId('tee')!, context: storyContext);
      await ProfileRepository(db.db, clock: clock.call).save(const LearnerProfile(onboarded: true));
      final json = jsonDecode(await data.exportJson()) as Map<String, dynamic>;
      expect(json['format'], DataRepository.exportFormat);
      expect(((json['tables'] as Map)['vocab_entries'] as List).length, 1);
      expect(await data.exportVocabularyTsv(), contains('der Tee'));
      await data.deleteAll();
      for (final t in AppDatabase.learnerTables) {
        expect(await db.db.query(t), isEmpty, reason: t);
      }
    });
  });

  test('data survives closing and reopening the database (restart)', () async {
    final (e, _) = await vocab.saveLexeme(content.lexicon.byId('termin')!, context: storyContext);
    await vocab.recordReview(eventId: 'once', entryId: e.id, type: CardType.recognition, grade: Grade.good, assisted: false);
    await db.close();

    db = await testDb.open();
    vocab = VocabRepository(db.db, clock: clock.call, ids: ids.call);
    final again = await vocab.entry(e.id);
    expect(again!.headword, 'der Termin');
    expect((await vocab.contexts(e.id)).single.sentence, storyContext.sentence);
    // Replaying the same event after restart must not double count.
    final replay = await vocab.recordReview(eventId: 'once', entryId: e.id, type: CardType.recognition, grade: Grade.good, assisted: false);
    expect(replay.duplicate, isTrue);
    expect((await db.db.query('review_events')).length, 1);
  });

  group('drill statistics', () {
    test('weak words are those missed at least as often as hit, worst first', () async {
      final progress = ProgressRepository(db.db, clock: clock.call, ids: ids.call);
      Future<void> attempt(String lexeme, DrillMode m, bool ok) =>
          progress.recordAttempt(activityType: 'drill', activityId: 'drill', itemId: drillItemId(lexeme, m), correct: ok, assisted: false);
      await attempt('termin', DrillMode.article, false);
      await attempt('termin', DrillMode.meaning, false);
      await attempt('termin', DrillMode.spell, true);
      await attempt('gehen', DrillMode.meaning, true);
      await attempt('gehen', DrillMode.perfekt, true);
      await attempt('kaffee', DrillMode.article, false);
      await attempt('kaffee', DrillMode.spell, false);
      await attempt('kaffee', DrillMode.meaning, false);
      expect(await weakLexemeIds(progress), ['kaffee', 'termin']);
      final stats = await progress.itemStats('drill');
      expect(stats[drillItemId('termin', DrillMode.article)], (right: 0, wrong: 1));
      expect(await progress.itemStats('listening'), isEmpty);
    });
  });

  group('sentence mining', () {
    test('a saved sentence gets one cloze card and is not duplicated', () async {
      final (e, existed) = await vocab.saveSentence(sentence: 'Ich brauche einen Termin.', target: 'Termin', sentenceTr: 'Bir randevuya ihtiyacım var.');
      expect(existed, isFalse);
      expect(e.kind, 'sentence');
      expect(e.lemma, 'Termin');
      expect((await vocab.cards(e.id)).map((c) => c.type), [CardType.cloze]);
      final (_, again) = await vocab.saveSentence(sentence: 'Ich brauche einen Termin.', target: 'brauche');
      expect(again, isTrue);
      expect(blankTarget(e.headword, e.lemma), 'Ich brauche einen _____.');
      expect(blankTarget('Termin ist morgen. Der Termin!', 'termin'), '_____ ist morgen. Der Termin!');
    });
  });

  test('appearance preferences survive a save', () async {
    final repo = ProfileRepository(db.db, clock: clock.call);
    await repo.save(const LearnerProfile(onboarded: true, themeMode: 'dark', textScale: 1.2, readableFont: true));
    final back = await repo.load();
    expect(back.themeMode, 'dark');
    expect(back.textScale, 1.2);
    expect(back.readableFont, isTrue);
  });

  test('a shared collection imports into a new collection on another device', () async {
    final (k, _) = await vocab.saveLexeme(content.lexicon.byId('kaffee')!);
    final manual = await vocab.saveManual(headword: 'die Kastanie', meaningTr: 'kestane', kind: 'noun', article: 'die');
    await vocab.saveSentence(sentence: 'Ich trinke Kaffee.', target: 'Kaffee');
    final col = await vocab.createCollection('Kafe');
    await vocab.setInCollection(col, k.id, true);
    await vocab.setInCollection(col, manual.id, true);
    final pack = packFromEntries('Kafe', await vocab.list(VocabQuery(collectionId: col)));
    expect(pack.lexemeIds, ['kaffee']);
    expect(pack.custom.single.headword, 'die Kastanie');

    final decoded = WordPack.decode(pack.encode())!;
    final result = await importPack(decoded, repo: vocab, lexicon: content.lexicon);
    expect(result.alreadySaved, 2, reason: 'both words already exist on this device');
    expect(result.added, 0);
    expect((await vocab.list(VocabQuery(collectionId: result.collectionId))).length, 2);
  });
}
