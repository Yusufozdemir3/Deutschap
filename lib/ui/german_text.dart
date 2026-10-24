import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/theme/app_theme.dart';
import '../learning/text/tokenizer.dart';

/// A tapped word with the sentence it belongs to.
class WordTap {
  const WordTap({required this.surface, required this.sentence, required this.sentenceWords, required this.wordIndex, String? lineText})
      : lineText = lineText ?? sentence;
  final String surface;
  final String sentence;

  /// The whole text the word was tapped in (may hold several sentences).
  final String lineText;
  final List<String> sentenceWords;

  /// Index of [surface] within [sentenceWords].
  final int wordIndex;
}

/// German text where every word can be tapped. Words already in the
/// learner's library get a subtle underline.
class TappableGermanText extends StatefulWidget {
  const TappableGermanText(
    this.text, {
    super.key,
    required this.onWordTap,
    this.style,
    this.isKnown,
    this.textAlign = TextAlign.start,
  });

  final String text;
  final void Function(WordTap tap) onWordTap;
  final TextStyle? style;

  /// Returns true for surfaces that are in the learner's library.
  final bool Function(String surface)? isKnown;
  final TextAlign textAlign;

  @override
  State<TappableGermanText> createState() => _TappableGermanTextState();
}

class _TappableGermanTextState extends State<TappableGermanText> {
  late List<TextToken> _tokens;
  final _recognizers = <int, TapGestureRecognizer>{};
  int? _selected;

  @override
  void initState() {
    super.initState();
    _build();
  }

  @override
  void didUpdateWidget(TappableGermanText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _dispose();
      _build();
    }
  }

  void _build() {
    _tokens = tokenize(widget.text);
    for (final t in _tokens.where((t) => t.isWord)) {
      _recognizers[t.start] = TapGestureRecognizer()..onTap = () => _tap(t);
    }
  }

  void _tap(TextToken t) {
    setState(() => _selected = t.start);
    final (s, e) = sentenceBounds(widget.text, t.start);
    final sentence = widget.text.substring(s, e);
    final sentenceWords = words(sentence);
    final index = _tokens.where((x) => x.isWord && x.start >= s && x.start < t.start).length;
    widget.onWordTap(WordTap(surface: t.text, sentence: sentence.trim(), sentenceWords: sentenceWords, wordIndex: index, lineText: widget.text));
  }

  void _dispose() {
    for (final r in _recognizers.values) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final base = widget.style ?? context.reading;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          for (final t in _tokens)
            if (!t.isWord)
              TextSpan(text: t.text)
            else
              TextSpan(
                text: t.text,
                recognizer: _recognizers[t.start],
                mouseCursor: SystemMouseCursors.click,
                style: t.start == _selected
                    ? TextStyle(backgroundColor: p.accentSoft)
                    : (widget.isKnown?.call(t.text) ?? false)
                        ? TextStyle(decoration: TextDecoration.underline, decorationColor: p.accent, decorationStyle: TextDecorationStyle.dotted, decorationThickness: 2)
                        : null,
              ),
        ],
      ),
      textAlign: widget.textAlign,
    );
  }
}
