import 'dart:async';

import 'package:deutschap/app/app.dart';
import 'package:deutschap/app/providers.dart';
import 'package:deutschap/app/router.dart';
import 'package:deutschap/core/audio/speech_service.dart';
import 'package:deutschap/core/clock.dart';
import 'package:deutschap/core/db/app_database.dart';
import 'package:deutschap/features/profile/data/profile_repository.dart';
import 'package:deutschap/features/profile/domain/learner_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';
import '../helpers/test_db.dart';

/// End-to-end learner journeys (master spec §38) against a real SQLite
/// database file, so "restart" means closing and reopening that file.
void main() {
  final content = loadTestContent();
  late TestDb testDb;
  late FakeClock clock;

  setUp(() async {
    testDb = await TestDb.create();
    clock = FakeClock(DateTime(2026, 3, 2, 9));
  });
  tearDown(() => testDb.dispose());

  Future<(ProviderContainer, AppDatabase)> boot(WidgetTester tester, {bool onboarded = true}) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = await tester.runAsync(() => testDb.open());
    if (onboarded) {
      await tester.runAsync(() => ProfileRepository(db!.db, clock: clock.call).save(const LearnerProfile(onboarded: true, name: 'Deniz')));
    }
    final container = ProviderContainer(overrides: [
      bootstrapProvider.overrideWith((ref) async => AppServices(database: db!, content: content)),
      speechServiceProvider.overrideWithValue(SilentSpeechService()),
      clockProvider.overrideWithValue(clock.call),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const DeutschapApp()));
    await settle(tester);
    return (container, db!);
  }

  Future<void> shutdown(WidgetTester tester, ProviderContainer c, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    c.dispose();
    await tester.runAsync(() => db.close());
  }

  Future<List<Map<String, Object?>>> query(WidgetTester tester, AppDatabase db, String sql) async =>
      (await tester.runAsync(() => db.db.rawQuery(sql)))!;

  testWidgets('onboarding leads to a home screen with an explained recommendation (Journey E)', (tester) async {
    final (c, db) = await boot(tester, onboarded: false);
    expect(find.text('Başlayalım'), findsOneWidget);
    await tapAndSettle(tester, find.text('Başlayalım'));
    for (var i = 0; i < 4; i++) {
      await tapAndSettle(tester, find.text('Devam'));
    }
    await tapAndSettle(tester, find.text('Hazırım'));
    expect(find.text('Bugün için önerimiz'), findsOneWidget);
    expect(find.textContaining('Neden?'), findsOneWidget);
    expect(find.text('Selamlaşma ve vedalaşma'), findsWidgets, reason: 'a new learner starts with lesson 1');
    final rows = await query(tester, db, 'SELECT data FROM learner_profile');
    expect(rows.single['data'].toString(), contains('"onboarded":true'));
    await shutdown(tester, c, db);
  });

  testWidgets('story word → library with context → review (Journey A)', (tester) async {
    final (c, db) = await boot(tester);
    unawaited(c.read(routerProvider).push('/episode/nib_e3_a1'));
    await settle(tester);
    await tapAndSettle(tester, find.text('Başla'));
    // First narration: "Du brauchst einen Termin beim Bürgeramt – für die Anmeldung."
    await tester.tapOnText(find.textRange.ofSubstring('Termin').first);
    await settle(tester);
    expect(find.text('Kaydet'), findsWidgets);
    await tapAndSettle(tester, find.text('Kaydet').first);
    final entries = await query(tester, db, 'SELECT e.headword, c.source_type, c.source_id, c.sentence FROM vocab_entries e JOIN vocab_contexts c ON c.entry_id = e.id');
    expect(entries.single['headword'], 'der Termin');
    expect(entries.single['source_type'], 'story');
    expect(entries.single['source_id'], 'nib_e3_a1');
    expect(entries.single['sentence'].toString(), contains('Termin'));

    Navigator.of(tester.element(find.text('Cümle'))).pop(); // close the sheet
    await settle(tester);
    unawaited(c.read(routerProvider).push('/review'));
    await settle(tester);
    await tapAndSettle(tester, find.text('Anlamı göster'));
    expect(find.text('randevu'), findsOneWidget);
    expect(find.textContaining('Termin'), findsWidgets, reason: 'the source sentence is shown with the card');
    await tapAndSettle(tester, find.text('Hatırladım'));
    expect(find.text('Tekrar tamamlandı'), findsOneWidget);
    expect(find.textContaining('1 kartı ipucusuz hatırladın'), findsOneWidget);
    final events = await query(tester, db, 'SELECT grade, assisted FROM review_events');
    expect(events.single['grade'], 2);
    await shutdown(tester, c, db);
  });

  testWidgets('conversation understands meaning, corrects, and records usage (Journey B, offline engine)', (tester) async {
    final (c, db) = await boot(tester);
    await tester.runAsync(() => c.read(vocabRepositoryProvider).saveLexeme(content.lexicon.byId('kaffee')!));
    unawaited(c.read(routerProvider).push('/scenario/cafe'));
    await settle(tester);
    await tapAndSettle(tester, find.text('Konuşmayı başlat'));
    Future<void> say(String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tapAndSettle(tester, find.byTooltip('Gönder'));
    }

    await say('Ich möchte ein Kaffee');
    expect(find.textContaining('Anlaşıldı ✓'), findsOneWidget);
    expect(find.text('Ich möchte einen Kaffee'), findsOneWidget);
    await say('Für hier, bitte.');
    await say('Kann ich mit Karte zahlen?');
    expect(find.text('Hedefe ulaştın!'), findsOneWidget);
    final sessions = await query(tester, db, 'SELECT status, transcript, corrections FROM conversation_sessions');
    expect(sessions.single['status'], 'completed');
    expect(sessions.single['transcript'], isNull, reason: 'transcripts are not kept by default');
    expect(sessions.single['corrections'].toString(), contains('akkusativ_der'));
    final usage = await query(tester, db, "SELECT sentence FROM vocab_contexts WHERE source_type = 'conversation'");
    expect(usage.single['sentence'], 'Ich möchte ein Kaffee');
    await shutdown(tester, c, db);
  });

  testWidgets('reading: save a word with its sentence (Journey C)', (tester) async {
    final (c, db) = await boot(tester);
    unawaited(c.read(routerProvider).push('/reader/builtin:r_mein_zimmer'));
    await settle(tester);
    await tester.tapOnText(find.textRange.ofSubstring('Lampe').first);
    await settle(tester);
    await tapAndSettle(tester, find.text('Kaydet').first);
    final rows = await query(tester, db, 'SELECT e.headword, c.source_type, c.sentence FROM vocab_entries e JOIN vocab_contexts c ON c.entry_id = e.id');
    expect(rows.single['headword'], 'die Lampe');
    expect(rows.single['source_type'], 'reading');
    expect(rows.single['sentence'], 'Die Lampe ist alt.');
    await shutdown(tester, c, db);
  });

  testWidgets('lesson progress and vocabulary survive a restart (Journey D)', (tester) async {
    var (c, db) = await boot(tester);
    unawaited(c.read(routerProvider).push('/lesson/u1l1'));
    await settle(tester);
    await tapAndSettle(tester, find.text('Kaydet').first); // save "Hallo"
    await tapAndSettle(tester, find.text('Devam'));
    await tapAndSettle(tester, find.text('Devam'));
    await shutdown(tester, c, db);

    (c, db) = await boot(tester);
    final entries = await query(tester, db, 'SELECT headword FROM vocab_entries');
    expect(entries.single['headword'], 'Hallo');
    expect(find.text('Kaldığın yerden devam et'), findsOneWidget, reason: 'home offers to continue');
    unawaited(c.read(routerProvider).push('/lesson/u1l1'));
    await settle(tester);
    expect(find.text('Kaldığın yerden devam ediyorsun.'), findsOneWidget);
    expect(find.text('Fırında, sabah 8'), findsOneWidget, reason: 'resumes at the dialogue step');
    final events = await query(tester, db, 'SELECT COUNT(*) AS n FROM review_events');
    expect(events.single['n'], 0, reason: 'no phantom review events');
    await shutdown(tester, c, db);
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> tapAndSettle(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await settle(tester);
}
