import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/reading.dart';
import '../../../ui/german_text.dart';
import '../../../ui/widgets.dart';
import '../../home/domain/recommender.dart';
import '../../vocabulary/application/vocab_providers.dart';
import '../../vocabulary/domain/vocab_entry.dart';
import '../../vocabulary/presentation/word_sheet.dart';
import '../data/reading_repository.dart';

class _Para {
  const _Para(this.de, this.tr);
  final String de;
  final String? tr;
}

/// Reading workspace for built-in texts and the learner's own text.
/// Every word is tappable; the position is saved as the learner scrolls.
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key, required this.docId});
  final String docId;
  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  ReadingDoc? _doc;
  ReadingText? _builtin;
  List<_Para> _paras = const [];
  final _keys = <GlobalKey>[];
  final _scroll = ScrollController();
  final _shownTr = <int>{};
  int _position = 0;
  bool _loading = true;
  String? _error;
  int? _qPicked;
  int _q = 0;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(readingRepositoryProvider);
    try {
      if (widget.docId.startsWith('builtin:')) {
        final r = ref.read(contentProvider).reading(widget.docId.substring('builtin:'.length));
        if (r == null) throw StateError('missing');
        _builtin = r;
        _doc = await repo.openBuiltin(r.id, r.title, r.body);
        _paras = [for (final p in r.paragraphs) _Para(p.de, p.tr)];
      } else {
        final d = await repo.doc(widget.docId);
        if (d == null) throw StateError('missing');
        _doc = d;
        _paras = [
          for (final p in d.body.split(RegExp(r'\n\s*\n|\n')))
            if (p.trim().isNotEmpty) _Para(p.trim(), null),
        ];
      }
      _keys.addAll(List.generate(_paras.length, (_) => GlobalKey()));
      _position = _doc!.position.clamp(0, _paras.isEmpty ? 0 : _paras.length - 1);
    } catch (e) {
      _error = 'Bu metin bulunamadı ya da silinmiş.';
    }
    if (!mounted) return;
    setState(() => _loading = false);
    if (_position > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[_position].currentContext;
        if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.05);
      });
    }
  }

  bool _onScrollEnd(ScrollEndNotification n) {
    var first = 0;
    for (var i = 0; i < _keys.length; i++) {
      final box = _keys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      if (top + box.size.height > kToolbarHeight + MediaQuery.of(context).padding.top + 8) {
        first = i;
        break;
      }
    }
    if (first != _position) {
      _position = first;
      ref.read(readingRepositoryProvider).savePosition(_doc!.id, first).then((_) => ref.bumpData());
    }
    return false;
  }

  Future<void> _delete() async {
    final ok = await confirm(
      context,
      title: 'Metni sil?',
      message: 'Metin bu cihazdan silinir. Bu metinden kaydettiğin kelimeler, cümleleriyle birlikte kelime defterinde kalır.',
      confirmLabel: 'Sil',
      destructive: true,
    );
    if (!ok) return;
    await ref.read(readingRepositoryProvider).delete(_doc!.id);
    ref.bumpData();
    if (mounted) closeOrHome(context);
  }

  Future<void> _finish() async {
    if (_finished) return;
    setState(() => _finished = true);
    await ref.read(progressRepositoryProvider).logActivity(ActivityKind.reading, refId: _doc!.builtinId ?? _doc!.id);
    ref.bumpData();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingView());
    if (_error != null) return Scaffold(appBar: AppBar(leading: const BackOrHomeButton()), body: ErrorState(message: _error!));
    final doc = _doc!;
    final known = ref.watch(knownSurfacesProvider);
    final source = SourceContext(type: SourceType.reading, sourceId: doc.id, title: doc.title);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        title: Text(doc.title, style: context.text.titleMedium!.copyWith(fontFamily: 'Literata'), overflow: TextOverflow.ellipsis),
        actions: [
          if (doc.source == ReadingSource.pasted) IconButton(onPressed: _delete, icon: const Icon(Icons.delete_outline_rounded), tooltip: 'Metni sil'),
        ],
      ),
      body: NotificationListener<ScrollEndNotification>(
        onNotification: _onScrollEnd,
        child: ListView(
          controller: _scroll,
          padding: pagePadding,
          children: [
            PageWidth(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (_builtin != null) MetaLine(level: _builtin!.level, minutes: _builtin!.minutes, objective: _builtin!.topicTr),
                if (doc.source == ReadingSource.pasted)
                  Text('Kendi metnin · sadece bu cihazda. Çeviriler yalnızca sözlükteki kelimeler için gösterilir.', style: context.text.bodySmall),
                const SizedBox(height: 12),
                for (var i = 0; i < _paras.length; i++)
                  Padding(
                    key: _keys[i],
                    padding: const EdgeInsets.only(bottom: 18),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      TappableGermanText(
                        _paras[i].de,
                        isKnown: (w) => known.contains(w.toLowerCase()),
                        onWordTap: (t) => showWordSheet(context, tap: t, source: source, sentenceTr: _paras[i].tr),
                      ),
                      Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                        SpeakButton(_paras[i].de, size: 20),
                        SpeakButton(_paras[i].de, slow: true, size: 20),
                        if (_paras[i].tr != null)
                          TextButton(
                            onPressed: () => setState(() => _shownTr.contains(i) ? _shownTr.remove(i) : _shownTr.add(i)),
                            child: Text(_shownTr.contains(i) ? 'Çeviriyi gizle' : 'Paragraf çevirisi'),
                          ),
                      ]),
                      if (_shownTr.contains(i)) Text(_paras[i].tr!, style: context.text.bodyMedium!.copyWith(color: p.inkMuted)),
                    ]),
                  ),
                if (_builtin != null && _builtin!.questions.isNotEmpty) ...[
                  const SectionTitle('Anladın mı?'),
                  _questions(context, _builtin!),
                ] else ...[
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _finished ? null : _finish, child: Text(_finished ? 'Okundu olarak işaretlendi' : 'Okumayı bitirdim')),
                ],
              ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _questions(BuildContext context, ReadingText r) {
    final p = context.palette;
    if (_q >= r.questions.length) {
      return const FeedbackPanel(positive: true, title: 'Metni bitirdin', body: 'Kaydettiğin kelimeler tekrar planında seni bekliyor.');
    }
    final q = r.questions[_q];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(q.questionTr, style: context.text.titleSmall),
        const SizedBox(height: 8),
        for (var i = 0; i < q.options.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: AppCard(
              onTap: _qPicked == null ? () => setState(() => _qPicked = i) : null,
              color: _qPicked == null ? null : (i == q.answer ? p.successSoft : (i == _qPicked ? p.dangerSoft : null)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Text(q.options[i]),
            ),
          ),
        if (_qPicked != null) ...[
          Text(q.explainTr, style: context.text.bodySmall),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              setState(() {
                _q++;
                _qPicked = null;
              });
              if (_q >= r.questions.length) _finish();
            },
            child: const Text('Devam'),
          ),
        ],
      ]),
    );
  }
}
