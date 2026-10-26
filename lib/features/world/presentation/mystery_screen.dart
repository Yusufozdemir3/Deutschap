import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/world.dart';
import '../../../ui/widgets.dart';
import '../../vocabulary/domain/vocab_entry.dart';
import '../application/world_providers.dart';
import '../domain/world_progress.dart';

/// The detective board for "Neu in Berlin". Clues appear as the story
/// advances and are solved when their words are recalled without help,
/// which ties the story to vocabulary review.
class MysteryScreen extends ConsumerWidget {
  const MysteryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final content = ref.watch(contentProvider);
    final facts = ref.watch(progressFactsProvider);
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Gizem panosu')),
      body: AsyncView<ProgressFacts>(
        value: facts,
        onRetry: () => ref.invalidate(progressFactsProvider),
        builder: (f) {
          final states = {for (final c in content.clues) c.id: clueState(c, f)};
          final solved = states.values.where((s) => s == ClueState.solved).length;
          final revealed = states.values.where((s) => s != ClueState.hidden).length;
          return ListView(
            padding: pagePadding,
            children: [
              PageWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Wer ist M.? Wer ist F.?', style: context.text.headlineSmall!.copyWith(fontFamily: context.serif)),
                  const SizedBox(height: 4),
                  Text('$revealed / ${content.clues.length} ipucu bulundu · $solved çözüldü', style: context.text.titleSmall),
                  const SizedBox(height: 6),
                  Text('İpuçları hikâyede ortaya çıkar. Bir ipucunun kelimelerini tekrarlarda ipucusuz hatırladığında o ipucunu "çözmüş" olursun.',
                      style: context.text.bodySmall),
                  const SizedBox(height: 12),
                  for (var i = 0; i < content.clues.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ClueCard(clue: content.clues[i], state: states[content.clues[i].id]!, facts: f, tilt: i.isEven ? -0.008 : 0.008),
                    ),
                ]),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ClueCard extends ConsumerWidget {
  const _ClueCard({required this.clue, required this.state, required this.facts, required this.tilt});
  final Clue clue;
  final ClueState state;
  final ProgressFacts facts;
  final double tilt;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final lexicon = ref.watch(contentProvider).lexicon;
    final reduce = MediaQuery.of(context).disableAnimations;
    Widget card;
    if (state == ClueState.hidden) {
      card = AppCard(
        color: p.surfaceAlt,
        child: Row(children: [
          Text('?', style: context.text.displaySmall!.copyWith(color: p.inkMuted, fontFamily: context.serif)),
          const SizedBox(width: 16),
          Expanded(child: Text('Hikâyenin ${clue.episode}. bölümünü bitirince ortaya çıkar.', style: context.text.bodyMedium)),
        ]),
      );
    } else {
      final unsaved = clue.lexemes.where((l) => !facts.savedLexemes.contains(l)).toList();
      card = AppCard(
        borderColor: state == ClueState.solved ? p.success : p.accent,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.push_pin_rounded, color: p.danger, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(clue.titleDe, style: context.text.titleLarge!.copyWith(fontFamily: context.serif))),
            if (state == ClueState.solved) Pill('ÇÖZÜLDÜ', icon: Icons.verified_rounded, color: p.successSoft, textColor: p.success),
          ]),
          Text(clue.titleTr, style: context.text.bodySmall),
          const SizedBox(height: 8),
          Text(clue.textTr, style: context.text.bodyLarge),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('„${clue.quoteDe}“', style: context.reading.copyWith(fontSize: 16, fontStyle: FontStyle.italic))),
            SpeakButton(clue.quoteDe, size: 20),
          ]),
          const SizedBox(height: 10),
          Text('İpucunun kelimeleri', style: context.text.labelSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final id in clue.lexemes)
              if (lexicon.byId(id) case final l?)
                Tag(
                  l.headword,
                  icon: facts.recalledLexemes.contains(id)
                      ? Icons.check_circle_rounded
                      : (facts.savedLexemes.contains(id) ? Icons.bookmark_rounded : Icons.bookmark_border_rounded),
                  selected: facts.recalledLexemes.contains(id),
                  onTap: () => context.push('/lexeme/$id'),
                ),
          ]),
          const SizedBox(height: 6),
          Text(
            state == ClueState.solved
                ? 'Bu ipucunun bütün kelimelerini ipucusuz hatırladın.'
                : '✓ = ipucusuz hatırlandı · dolu işaret = kayıtlı, tekrar bekliyor · boş = henüz kaydedilmedi',
            style: context.text.bodySmall,
          ),
          if (unsaved.isNotEmpty) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                final repo = ref.read(vocabRepositoryProvider);
                for (final id in unsaved) {
                  await repo.saveLexeme(lexicon.byId(id)!,
                      context: SourceContext(type: SourceType.story, sourceId: '', title: 'Gizem panosu: ${clue.titleDe}', sentence: clue.quoteDe));
                }
                ref.bumpData();
                if (context.mounted) showToast(context, 'Kelimeler tekrar planına eklendi');
              },
              icon: const Icon(Icons.bookmark_add_outlined),
              label: Text('${unsaved.length} kelimeyi kaydet'),
            ),
          ],
        ]),
      );
    }
    return reduce ? card : Transform.rotate(angle: tilt, child: card);
  }
}
