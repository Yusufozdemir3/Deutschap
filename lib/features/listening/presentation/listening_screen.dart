import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/reading.dart';
import '../../../core/audio/speech_service.dart';
import '../../../learning/answer_checker.dart';
import '../../../ui/german_text.dart';
import '../../../ui/widgets.dart';
import '../../home/domain/recommender.dart';
import '../../vocabulary/application/vocab_providers.dart';
import '../../vocabulary/domain/vocab_entry.dart';
import '../../vocabulary/presentation/word_sheet.dart';

/// Listening practice: play the whole track (one pitch per speaker),
/// answer questions without the text, then optionally reveal the
/// transcript and try a short dictation.
class ListeningScreen extends ConsumerStatefulWidget {
  const ListeningScreen({super.key, required this.trackId});
  final String trackId;
  @override
  ConsumerState<ListeningScreen> createState() => _ListeningScreenState();
}

class _ListeningScreenState extends ConsumerState<ListeningScreen> {
  static const _pitches = [1.0, 0.8, 1.2, 0.9];

  bool _playing = false;
  bool _slow = false;
  bool _noVoice = false;
  int? _current;
  int _playToken = 0;
  bool _transcript = false;
  final _shownTr = <int>{};
  final _answers = <int, int>{};
  bool _logged = false;

  /// Shadowing: line being practised and whether it is the learner's turn.
  int? _shadowLine;
  bool _shadowRepeat = false;
  Duration _shadowPause = Duration.zero;

  ListeningTrack? get _track => ref.read(contentProvider).track(widget.trackId);

  /// Kept so playback can be stopped in [dispose], when ref is gone.
  late final SpeechService _speech;

  @override
  void initState() {
    super.initState();
    _speech = ref.read(speechServiceProvider);
  }

  @override
  void dispose() {
    _playToken++;
    _speech.stop();
    super.dispose();
  }

  double _pitchFor(ListeningTrack t, String speaker) => _pitches[t.speakers.indexOf(speaker) % _pitches.length];

  Future<void> _playAll(ListeningTrack t, {int from = 0}) async {
    final token = ++_playToken;
    setState(() => _playing = true);
    final speech = _speech;
    for (var i = from; i < t.lines.length; i++) {
      if (!mounted || token != _playToken) return;
      setState(() => _current = i);
      final ok = await speech.speak(t.lines[i].de, slow: _slow, wait: true, pitch: _pitchFor(t, t.lines[i].speaker));
      if (!ok) {
        if (mounted) setState(() => _noVoice = _transcript = true);
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    if (mounted && token == _playToken) setState(() => _playing = false);
  }

  /// Plays each line, then leaves a pause about as long as the line for
  /// the learner to repeat it aloud.
  Future<void> _shadow(ListeningTrack t) async {
    final token = ++_playToken;
    setState(() => _playing = false);
    for (var i = 0; i < t.lines.length; i++) {
      if (!mounted || token != _playToken) return;
      setState(() {
        _shadowLine = i;
        _shadowRepeat = false;
      });
      final ok = await _speech.speak(t.lines[i].de, slow: true, wait: true, pitch: _pitchFor(t, t.lines[i].speaker));
      if (!ok) {
        if (mounted) setState(() => _noVoice = _transcript = true);
        break;
      }
      if (!mounted || token != _playToken) return;
      final words = t.lines[i].de.split(RegExp(r'\s+')).length;
      final pause = Duration(milliseconds: 1200 + words * 600);
      setState(() {
        _shadowRepeat = true;
        _shadowPause = pause;
      });
      await Future<void>.delayed(pause);
    }
    if (mounted && token == _playToken) setState(() => _shadowLine = null);
  }

  void _stopShadow() {
    _playToken++;
    _speech.stop();
    setState(() => _shadowLine = null);
  }

  void _stop() {
    _playToken++;
    ref.read(speechServiceProvider).stop();
    setState(() => _playing = false);
  }

  Future<void> _playLine(ListeningTrack t, int i) async {
    _playToken++;
    setState(() {
      _playing = false;
      _current = i;
    });
    final ok = await ref.read(speechServiceProvider).speak(t.lines[i].de, slow: _slow, pitch: _pitchFor(t, t.lines[i].speaker));
    if (!ok && mounted) setState(() => _noVoice = _transcript = true);
  }

  Future<void> _answer(ListeningTrack t, int q, int option) async {
    setState(() => _answers[q] = option);
    await ref.read(progressRepositoryProvider).recordAttempt(
          activityType: 'listening',
          activityId: t.id,
          itemId: '${t.id}#q$q',
          correct: t.questions[q].answer == option,
          assisted: _transcript && !_noVoice,
        );
    if (_answers.length == t.questions.length && !_logged) {
      _logged = true;
      final right = [for (final e in _answers.entries) if (t.questions[e.key].answer == e.value) 1].length;
      await ref.read(progressRepositoryProvider).logActivity(ActivityKind.listening, refId: t.id, summary: '$right/${t.questions.length}');
      ref.bumpData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _track;
    if (t == null) return Scaffold(appBar: AppBar(leading: const BackOrHomeButton()), body: const ErrorState(message: 'Bu dinleme bulunamadı.'));
    final p = context.palette;
    final known = ref.watch(knownSurfacesProvider);
    final source = SourceContext(type: SourceType.reading, sourceId: 'listen:${t.id}', title: t.title);
    final allAnswered = _answers.length == t.questions.length;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: Text(t.title, style: context.text.titleMedium!.copyWith(fontFamily: context.serif), overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              MetaLine(level: t.level, minutes: t.minutes, objective: '${t.kindTr} · ${t.topicTr}'),
              const SizedBox(height: 12),
              AppCard(
                color: p.accentSoft,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('1. Önce metne bakmadan dinle', style: context.text.titleSmall),
                  const SizedBox(height: 4),
                  Text(
                    t.speakers.length > 1
                        ? '${t.speakers.length} konuşmacı var; her biri farklı tonda okunur. İstediğin kadar tekrar dinle.'
                        : 'İstediğin kadar tekrar dinle. Yavaş mod, sesleri ayırmayı kolaylaştırır.',
                    style: context.text.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    FilledButton.icon(
                      onPressed: _playing ? _stop : () => _playAll(t),
                      icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded),
                      label: Text(_playing ? 'Durdur' : (_current == null ? 'Dinle' : 'Baştan dinle')),
                    ),
                    FilterChip(
                      label: const Text('Yavaş'),
                      avatar: const Icon(Icons.slow_motion_video_rounded, size: 18),
                      selected: _slow,
                      onSelected: (v) => setState(() => _slow = v),
                    ),
                  ]),
                  if (_playing && _current != null) ...[
                    const SizedBox(height: 10),
                    LinearProgressIndicator(value: (_current! + 1) / t.lines.length),
                  ],
                  if (_noVoice) ...[
                    const SizedBox(height: 8),
                    Text('Bu cihazda Almanca ses bulunamadı; metni okuyarak devam edebilirsin.', style: context.text.bodySmall),
                  ],
                ]),
              ),
              const SectionTitle('2. Anladın mı?'),
              for (var qi = 0; qi < t.questions.length; qi++) _question(context, t, qi),
              SectionTitle(
                '3. Metin',
                trailing: _transcript
                    ? null
                    : TextButton.icon(
                        onPressed: () => setState(() => _transcript = true),
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Göster'),
                      ),
              ),
              if (!_transcript)
                Text(allAnswered ? 'Şimdi metni açıp duyduklarınla karşılaştır.' : 'Soruları önce dinleyerek cevaplamayı dene. Metni açmak serbest ama yardım sayılır.',
                    style: context.text.bodySmall)
              else
                for (var i = 0; i < t.lines.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
                      decoration: BoxDecoration(
                        color: _current == i ? p.accentSoft : null,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (t.speakers.length > 1) Text(t.lines[i].speaker, style: context.text.labelSmall!.copyWith(color: p.inkMuted)),
                        TappableGermanText(
                          t.lines[i].de,
                          isKnown: (w) => known.contains(w.toLowerCase()),
                          onWordTap: (tap) => showWordSheet(context, tap: tap, source: source, sentenceTr: t.lines[i].tr),
                        ),
                        Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                          IconButton(
                            tooltip: 'Bu cümleyi dinle',
                            iconSize: 20,
                            icon: Icon(Icons.volume_up_rounded, color: p.primary),
                            onPressed: () => _playLine(t, i),
                          ),
                          TextButton(
                            onPressed: () => setState(() => _shownTr.contains(i) ? _shownTr.remove(i) : _shownTr.add(i)),
                            child: Text(_shownTr.contains(i) ? 'Çeviriyi gizle' : 'Çeviri'),
                          ),
                        ]),
                        if (_shownTr.contains(i)) Text(t.lines[i].tr, style: context.text.bodyMedium!.copyWith(color: p.inkMuted)),
                      ]),
                    ),
                  ),
              if (t.dictationLines().isNotEmpty) ...[
                const SectionTitle('4. Dikte (isteğe bağlı)'),
                Text('Cümleyi dinle ve duyduğunu yaz. Küçük yazım hataları "neredeyse" sayılır.', style: context.text.bodySmall),
                const SizedBox(height: 8),
                for (final i in t.dictationLines())
                  _Dictation(key: ValueKey('${t.id}#d$i'), line: t.lines[i], pitch: _pitchFor(t, t.lines[i].speaker), slow: _slow, trackId: t.id, index: i),
              ],
              const SectionTitle('5. Gölgeleme (isteğe bağlı)'),
              Text('Her cümle yavaşça okunur, ardından senin sesli tekrar etmen için bir duraklama gelir. Mikrofon gerekmez; '
                  'amaç ritmi ve vurguyu taklit etmek.', style: context.text.bodySmall),
              const SizedBox(height: 8),
              if (_shadowLine == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(onPressed: () => _shadow(t), icon: const Icon(Icons.record_voice_over_outlined), label: const Text('Gölgelemeye başla')),
                )
              else
                AppCard(
                  color: _shadowRepeat ? p.successSoft : p.accentSoft,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('${_shadowLine! + 1} / ${t.lines.length} · ${_shadowRepeat ? 'Şimdi sen tekrar et' : 'Dinle'}', style: context.text.labelMedium),
                    const SizedBox(height: 6),
                    Text(t.lines[_shadowLine!].de, style: context.reading.copyWith(fontSize: 20)),
                    const SizedBox(height: 8),
                    if (_shadowRepeat)
                      TweenAnimationBuilder<double>(
                        key: ValueKey('shadow$_shadowLine'),
                        tween: Tween(begin: 1, end: 0),
                        duration: _shadowPause,
                        builder: (_, v, _) => LinearProgressIndicator(value: v),
                      ),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: TextButton(onPressed: _stopShadow, child: const Text('Durdur'))),
                  ]),
                ),
              if (t.sourceTr != null) ...[
                const SizedBox(height: 16),
                Text('Kaynak: ${t.sourceTr}', style: context.text.labelSmall!.copyWith(color: p.inkMuted)),
              ],
              const SizedBox(height: 4),
              Text('Ses, cihazının metin okuma motoruyla üretilir; anadili konuşan birinin kaydı değildir.', style: context.text.labelSmall!.copyWith(color: p.inkMuted)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _question(BuildContext context, ListeningTrack t, int qi) {
    final p = context.palette;
    final q = t.questions[qi];
    final picked = _answers[qi];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(q.questionTr, style: context.text.titleSmall),
          const SizedBox(height: 8),
          for (final i in optionOrder(q.options.length, '${t.id}#$qi'))
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: AppCard(
                onTap: picked == null ? () => _answer(t, qi, i) : null,
                color: picked == null ? null : (i == q.answer ? p.successSoft : (i == picked ? p.dangerSoft : null)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                semanticLabel: picked == null ? q.options[i] : (i == q.answer ? '${q.options[i]}, doğru cevap' : q.options[i]),
                child: Text(q.options[i]),
              ),
            ),
          if (picked != null) Text(q.explainTr, style: context.text.bodySmall),
        ]),
      ),
    );
  }
}

class _Dictation extends ConsumerStatefulWidget {
  const _Dictation({super.key, required this.line, required this.pitch, required this.slow, required this.trackId, required this.index});
  final ListeningLine line;
  final double pitch;
  final bool slow;
  final String trackId;
  final int index;
  @override
  ConsumerState<_Dictation> createState() => _DictationState();
}

class _DictationState extends ConsumerState<_Dictation> {
  final _input = TextEditingController();
  AnswerCheck? _check;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final c = checkAnswer(_input.text, [widget.line.de]);
    setState(() => _check = c);
    await ref.read(progressRepositoryProvider).recordAttempt(
          activityType: 'listening',
          activityId: widget.trackId,
          itemId: '${widget.trackId}#d${widget.index}',
          correct: c.verdict.isAccepted,
          assisted: false,
        );
  }

  @override
  Widget build(BuildContext context) {
    final c = _check;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconButton(
              tooltip: 'Dinle',
              icon: Icon(Icons.volume_up_rounded, color: context.palette.primary),
              onPressed: () async {
                final ok = await ref.read(speechServiceProvider).speak(widget.line.de, slow: widget.slow, pitch: widget.pitch);
                if (!ok && context.mounted) showToast(context, 'Almanca ses yok; dikte bu cihazda yapılamıyor.');
              },
            ),
            IconButton(
              tooltip: 'Yavaş dinle',
              icon: Icon(Icons.slow_motion_video_rounded, color: context.palette.primary),
              onPressed: () => ref.read(speechServiceProvider).speak(widget.line.de, slow: true, pitch: widget.pitch),
            ),
            Expanded(
              child: TextField(
                controller: _input,
                enabled: c == null,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(hintText: 'Duyduğunu yaz…'),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _input.text.trim().isEmpty ? null : _verify(),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          if (c == null)
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(onPressed: _input.text.trim().isEmpty ? null : _verify, child: const Text('Kontrol et')),
            )
          else
            FeedbackPanel(
              positive: c.verdict.isAccepted,
              title: switch (c.verdict) {
                AnswerVerdict.correct => 'Doğru!',
                AnswerVerdict.correctWithNote => 'Kabul edildi',
                AnswerVerdict.nearMiss => 'Neredeyse!',
                AnswerVerdict.wrong => 'Doğrusu:',
              },
              body: [widget.line.de, ?c.noteTr, widget.line.tr].join('\n'),
            ),
        ]),
      ),
    );
  }
}
