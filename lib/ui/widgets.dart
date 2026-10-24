import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../app/providers.dart';
import '../app/theme/app_theme.dart';

/// Page padding used across screens (16px gutter on phones).
const pagePadding = EdgeInsets.fromLTRB(16, 8, 16, 32);

/// Constrains content on wide screens so lines stay readable.
class PageWidth extends StatelessWidget {
  const PageWidth({super.key, required this.child, this.max = 680});
  final Widget child;
  final double max;
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child),
      );
}

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(18), this.color, this.borderColor, this.semanticLabel});
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final Color? color;
  final Color? borderColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final content = Padding(padding: padding, child: child);
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: Material(
        color: color ?? p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radius),
          side: BorderSide(color: borderColor ?? p.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: onTap == null ? content : InkWell(onTap: onTap, child: content),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing, this.padding = const EdgeInsets.fromLTRB(2, 24, 2, 10)});
  final String title;
  final Widget? trailing;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: Row(
          children: [
            Expanded(child: Semantics(header: true, child: Text(title, style: context.text.titleMedium))),
            ?trailing,
          ],
        ),
      );
}

/// "A1 · 5 dk · objective" line every learning item shows.
class MetaLine extends StatelessWidget {
  const MetaLine({super.key, this.level, this.minutes, this.objective});
  final String? level;
  final int? minutes;
  final String? objective;
  @override
  Widget build(BuildContext context) {
    final parts = [?level, if (minutes != null) '$minutes dk'];
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (parts.isNotEmpty) Text(parts.join(' · '), style: context.text.labelSmall),
        if (objective != null) Text(objective!, style: context.text.bodySmall),
      ],
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.color, this.textColor, this.icon});
  final String label;
  final Color? color;
  final Color? textColor;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color ?? p.surfaceAlt, borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: textColor ?? p.ink), const SizedBox(width: 4)],
          Text(label, style: context.text.labelMedium!.copyWith(color: textColor ?? p.ink)),
        ],
      ),
    );
  }
}

/// der/die/das with colour AND text.
class ArticleBadge extends StatelessWidget {
  const ArticleBadge(this.article, {super.key});
  final String? article;
  @override
  Widget build(BuildContext context) {
    if (article == null) return const SizedBox.shrink();
    final c = context.palette.article(article);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(border: Border.all(color: c, width: 1.5), borderRadius: BorderRadius.circular(6)),
      child: Text(article!, style: context.text.labelMedium!.copyWith(color: c)),
    );
  }
}

/// Headword with a coloured article, e.g. [der] Termin.
class Headword extends StatelessWidget {
  const Headword({super.key, required this.lemma, this.article, this.style});
  final String lemma;
  final String? article;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) {
    final s = style ?? context.text.titleMedium!;
    if (article == null) return Text(lemma, style: s);
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '$article ', style: s.copyWith(color: context.palette.article(article))),
        TextSpan(text: lemma),
      ]),
      style: s,
      semanticsLabel: '$article $lemma',
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: context.palette.inkMuted),
            const SizedBox(height: 14),
            Text(title, style: context.text.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
            Text(message, style: context.text.bodyMedium!.copyWith(color: context.palette.inkMuted), textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 18), action!],
          ],
        ),
      );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.message, this.onRetry, this.details});
  final String message;
  final String? details;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, size: 40, color: context.palette.danger),
              const SizedBox(height: 12),
              Text(message, style: context.text.titleMedium, textAlign: TextAlign.center),
              if (details != null) ...[
                const SizedBox(height: 6),
                Text(details!, style: context.text.bodySmall, textAlign: TextAlign.center),
              ],
              if (onRetry != null) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded), label: const Text('Tekrar dene')),
              ],
            ],
          ),
        ),
      );
}

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label});
  final String? label;
  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          label: label ?? 'Yükleniyor',
          child: const Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
        ),
      );
}

/// Renders an [AsyncValue], keeping the previous value visible while a
/// refresh is in flight so screens do not flash a spinner after edits.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.builder, this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    if (value.hasValue) return builder(value.requireValue);
    if (value.hasError) {
      return ErrorState(message: 'Bir şeyler ters gitti.', details: 'Verilerin güvende; tekrar deneyebilirsin.', onRetry: onRetry);
    }
    return const LoadingView();
  }
}

/// Plays German text through TTS and tells the learner when no voice is
/// available instead of failing silently.
class SpeakButton extends ConsumerWidget {
  const SpeakButton(this.text, {super.key, this.slow = false, this.size = 22});
  final String text;
  final bool slow;
  final double size;
  @override
  Widget build(BuildContext context, WidgetRef ref) => IconButton(
        tooltip: slow ? 'Yavaş dinle' : 'Dinle',
        iconSize: size,
        icon: Icon(slow ? Icons.slow_motion_video_rounded : Icons.volume_up_rounded, color: context.palette.primary),
        onPressed: () async {
          final ok = await ref.read(speechServiceProvider).speak(text, slow: slow);
          if (!ok && context.mounted) {
            ScaffoldMessenger.of(context)
              ..hideCurrentSnackBar()
              ..showSnackBar(const SnackBar(content: Text('Bu cihazda Almanca ses bulunamadı. Metin her zaman görünür kalır.'), margin: EdgeInsets.fromLTRB(16, 0, 16, 84)));
          }
        },
      );
}

void showToast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    // Lifted above the sticky action buttons pages keep at the bottom.
    ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 2), margin: const EdgeInsets.fromLTRB(16, 0, 16, 84)));
}

/// Coloured feedback box after an answer.
class FeedbackPanel extends StatelessWidget {
  const FeedbackPanel({super.key, required this.positive, required this.title, this.body, this.extra, this.neutral = false});
  final bool positive;
  final bool neutral;
  final String title;
  final String? body;
  final Widget? extra;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bg = neutral ? p.accentSoft : (positive ? p.successSoft : p.dangerSoft);
    final fg = neutral ? p.accent : (positive ? p.success : p.danger);
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(neutral ? Icons.lightbulb_outline_rounded : (positive ? Icons.check_circle_rounded : Icons.info_outline_rounded), color: fg, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(title, style: context.text.titleSmall!.copyWith(color: fg))),
            ]),
            if (body != null) ...[const SizedBox(height: 6), Text(body!, style: context.text.bodyMedium)],
            if (extra != null) ...[const SizedBox(height: 8), extra!],
          ],
        ),
      ),
    );
  }
}

Future<bool> confirm(BuildContext context, {required String title, required String message, String confirmLabel = 'Evet', bool destructive = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Vazgeç')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: context.palette.danger) : null,
          onPressed: () => Navigator.pop(c, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Leaves a full-screen page. Pages opened from a deep link have nothing
/// to pop, so they go home instead of doing nothing.
void closeOrHome(BuildContext context) {
  final router = GoRouter.of(context);
  if (router.canPop()) {
    router.pop();
  } else {
    router.go('/heute');
  }
}

class BackOrHomeButton extends StatelessWidget {
  const BackOrHomeButton({super.key});
  @override
  Widget build(BuildContext context) => GoRouter.of(context).canPop()
      ? const BackButton()
      : IconButton(icon: const Icon(Icons.home_outlined), tooltip: 'Ana sayfa', onPressed: () => GoRouter.of(context).go('/heute'));
}
