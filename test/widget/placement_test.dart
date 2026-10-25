import 'package:deutschap/app/app.dart';
import 'package:deutschap/app/providers.dart';
import 'package:deutschap/app/router.dart';
import 'package:deutschap/core/audio/speech_service.dart';
import 'package:deutschap/core/clock.dart';
import 'package:deutschap/features/profile/data/profile_repository.dart';
import 'package:deutschap/features/profile/domain/learner_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';
import '../helpers/test_db.dart';
import 'journeys_test.dart' show settle;

void main() {
  final content = loadTestContent();

  testWidgets('a very strong A1 round opens the A2 questions and suggests the A2 path', (tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final testDb = (await tester.runAsync(TestDb.create))!;
    final db = (await tester.runAsync(() => testDb.open()))!;
    final clock = FakeClock(DateTime(2026, 3, 2, 9));
    await tester.runAsync(() => ProfileRepository(db.db, clock: clock.call).save(const LearnerProfile(onboarded: true, name: 'Deniz')));
    final container = ProviderContainer(overrides: [
      bootstrapProvider.overrideWith((ref) async => AppServices(database: db, content: content)),
      speechServiceProvider.overrideWithValue(SilentSpeechService()),
      clockProvider.overrideWithValue(clock.call),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const DeutschapApp()));
    await settle(tester);

    container.read(routerProvider).go('/onboarding/placement');
    await settle(tester);
    // Correct answers of the nine A1 questions, then the four A2 questions.
    const answers = [
      'hesap / fatura', 'Vaktim yok.', 'der Termin', 'heiße', 'einen', 'Heute gehe ich ins Café.', 'Leipzig', 'Salı 9:30', 'Sadece sabah',
      'Ich bin gestern nach Hamburg gefahren.', 'ich müde bin', 'mir', 'Otobüs rötar yaptı',
    ];
    for (final a in answers) {
      await tester.tap(find.text(a));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump();
    }
    await settle(tester);
    expect(find.text('A2 yoluna başla'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.runAsync(() => db.close());
    await tester.runAsync(() => testDb.dispose());
  });
}
