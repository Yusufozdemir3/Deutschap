import 'package:deutschap/app/providers.dart';
import 'package:deutschap/app/theme/app_theme.dart';
import 'package:deutschap/content/models/lesson.dart';
import 'package:deutschap/core/audio/speech_service.dart';
import 'package:deutschap/features/lesson/presentation/step_views.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_content.dart';

void main() {
  final content = loadTestContent();

  Future<StepOutcome?> run(WidgetTester tester, Widget Function(StepDone done) build, Future<void> Function() act) async {
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    StepOutcome? outcome;
    var finished = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        contentProvider.overrideWithValue(content),
        speechServiceProvider.overrideWithValue(SilentSpeechService()),
      ],
      child: MaterialApp(
        theme: AppTheme.build(Brightness.light),
        home: Scaffold(body: build((o) {
          outcome = o;
          finished = true;
        })),
      ),
    ));
    await tester.pumpAndSettle();
    await act();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kontrol et'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Devam'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
    return outcome;
  }

  WriteStep writeStep(String lessonId) => content.lesson(lessonId)!.steps.whereType<WriteStep>().single;

  testWidgets('writing: a complete, polite order passes', (tester) async {
    final out = await run(
      tester,
      (done) => WriteStepView(step: writeStep('u4l2'), done: done),
      () => tester.enterText(find.byType(TextField), 'Ich möchte einen Kaffee und ein Croissant, bitte.'),
    );
    expect(out!.correct, isTrue);
  });

  testWidgets('writing: a missing requirement and a grammar error are reported', (tester) async {
    final out = await run(
      tester,
      (done) => WriteStepView(step: writeStep('u4l2'), done: done),
      () async {
        await tester.enterText(find.byType(TextField), 'Ich möchte ein Kaffee, bitte.');
        await tester.pump();
      },
    );
    expect(out!.correct, isFalse);
  });

  testWidgets('listening without a German voice shows the text and does not count it as help', (tester) async {
    final step = content.lesson('u4l1')!.steps.whereType<ListenStep>().single;
    final out = await run(
      tester,
      (done) => ListenStepView(step: step, done: done),
      () async {
        expect(find.text(step.de), findsOneWidget);
        await tester.tap(find.text(step.options[step.answers.first]));
      },
    );
    expect(out!.correct, isTrue);
    expect(out.assisted, isFalse);
  });
}
