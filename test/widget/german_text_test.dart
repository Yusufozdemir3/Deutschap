import 'package:deutschap/app/theme/app_theme.dart';
import 'package:deutschap/ui/german_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('tapping a word reports it with its sentence', (tester) async {
    WordTap? tapped;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.build(Brightness.light),
      home: Scaffold(
        body: ListView(children: [
          TappableGermanText('Guten Morgen! Zwei Brötchen, bitte.', onWordTap: (t) => tapped = t),
        ]),
      ),
    ));
    await tester.tapOnText(find.textRange.ofSubstring('Brötchen'));
    await tester.pump();
    expect(tapped, isNotNull);
    expect(tapped!.surface, 'Brötchen');
    expect(tapped!.sentence, 'Zwei Brötchen, bitte.');
    expect(tapped!.wordIndex, 1);
  });
}
