import 'dart:async';

import 'package:deutschap/app/app.dart';
import 'package:deutschap/app/providers.dart';
import 'package:deutschap/app/router.dart';
import 'package:deutschap/core/audio/speech_service.dart';
import 'package:deutschap/core/clock.dart';
import 'package:deutschap/features/profile/data/profile_repository.dart';
import 'package:deutschap/features/profile/domain/learner_profile.dart';
import 'package:deutschap/features/vocabulary/data/vocab_repository.dart';
import 'package:deutschap/features/vocabulary/domain/vocab_entry.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';
import '../helpers/test_db.dart';
import 'journeys_test.dart' show settle;

/// Renders every route at phone size with large text and in dark mode.
/// Any layout overflow or build exception fails the test.
void main() {
  final content = loadTestContent();

  for (final variant in const [(textScale: 1.0, dark: false), (textScale: 1.6, dark: true)]) {
    testWidgets('all screens render at 375x812 (text ×${variant.textScale}, dark: ${variant.dark})', (tester) async {
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = variant.textScale;
      tester.platformDispatcher.platformBrightnessTestValue = variant.dark ? Brightness.dark : Brightness.light;
      addTearDown(() {
        tester.view.reset();
        tester.platformDispatcher.clearAllTestValues();
      });

      final testDb = (await tester.runAsync(TestDb.create))!;
      final db = (await tester.runAsync(() => testDb.open()))!;
      final clock = FakeClock(DateTime(2026, 3, 2, 9));
      String? entryId;
      await tester.runAsync(() async {
        await ProfileRepository(db.db, clock: clock.call).save(const LearnerProfile(onboarded: true, name: 'Deniz', interests: {'essen'}));
      });
      await tester.runAsync(() async {
        final repo = VocabRepository(db.db, clock: clock.call, ids: SeqIds().call);
        final (e, _) = await repo.saveLexeme(content.lexicon.byId('termin')!,
            context: const SourceContext(type: SourceType.story, sourceId: 'nib_e3_a1', title: 'Der Termin', sentence: 'Ich brauche einen Termin.'));
        entryId = e.id;
        await repo.saveLexeme(content.lexicon.byId('gehen')!);
      });
      final container = ProviderContainer(overrides: [
        bootstrapProvider.overrideWith((ref) async => AppServices(database: db, content: content)),
        speechServiceProvider.overrideWithValue(SilentSpeechService()),
        clockProvider.overrideWithValue(clock.call),
      ]);
      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const DeutschapApp()));
      await settle(tester);

      final routes = [
        '/heute', '/lernen', '/lernen?tab=stories', '/lernen?tab=talk', '/lernen?tab=read', '/entdecken', '/wortschatz', '/profil',
        '/lesson/u1l1', '/lesson/u4l2', '/lesson/u12l2', '/practice/akkusativ', '/practice/verbZweit', '/grammar/g_akkusativ', '/story/neu_in_berlin', '/episode/nib_e1_a1',
        '/scenario/termin', '/reader/builtin:r_ein_tag', '/paste', '/review', '/word/$entryId', '/lexeme/gehen',
        '/kiez', '/mystery', '/milestones', '/collections', '/progress', '/settings', '/settings/notifications', '/drill', '/drill?src=weak', '/drill/run?src=level%3AA1&mode=mixed&n=10', '/drill/run?src=level%3AA1&mode=match&n=10', '/drill/run?src=weak&mode=mixed&n=10', '/does-not-exist',
      ];
      final router = container.read(routerProvider);
      final previous = FlutterError.onError;
      FlutterError.onError = (d) {
        debugPrint(d.toString());
        previous?.call(d);
      };
      addTearDown(() => FlutterError.onError = previous);
      for (final r in routes) {
        if (r.startsWith('/heute') || r.startsWith('/lernen') || r.startsWith('/entdecken') || r.startsWith('/wortschatz') || r.startsWith('/profil')) {
          router.go(r);
        } else {
          router.go('/heute');
          await settle(tester);
          unawaited(router.push(r));
        }
        await settle(tester);
        final ex = tester.takeException();
        if (ex is FlutterError) debugPrint(ex.toStringDeep());
        expect(ex, isNull, reason: 'route $r');
      }

      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.runAsync(() => db.close());
      await tester.runAsync(testDb.dispose);
    });
  }
}
