import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/audio/voice_selection.dart';

final _voicesProvider = FutureProvider<(List<VoiceInfo>, VoiceInfo?)>((ref) async {
  final s = ref.watch(speechServiceProvider);
  return (await s.germanVoices(), await s.currentVoice());
});

const _sample = 'Guten Morgen! Ich hätte gern zwei Brötchen, bitte.';

/// Lists the German voices installed on the device. "Automatic" picks
/// the best installed, offline-capable voice.
class VoicePicker extends ConsumerWidget {
  const VoicePicker({super.key});

  Future<void> _choose(WidgetRef ref, String? name) async {
    await ref.read(profileProvider.notifier).edit((p) => p.copyWith(voiceName: () => name));
    // The speech service is rebuilt with the new voice; let it speak.
    await ref.read(speechServiceProvider).speak(_sample);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chosen = ref.watch(profileProvider.select((p) => p.valueOrNull?.voiceName));
    final data = ref.watch(_voicesProvider);
    final p = context.palette;
    return data.when(
      loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      error: (_, _) => Text('Ses listesi alınamadı.', style: context.text.bodySmall),
      data: (d) {
        final (voices, current) = d;
        if (voices.isEmpty) {
          return Text(
            'Bu cihazda seçilebilir bir Almanca ses listesi bulunamadı; varsayılan ses kullanılıyor.\n\n'
            'Daha iyi ses için (Android): Ayarlar → Erişilebilirlik → Metin okuma çıktısı → tercih edilen motor "Google" → Almanca ses verilerini indir.',
            style: context.text.bodySmall,
          );
        }
        Widget tile({required String title, String? subtitle, required bool selected, required VoidCallback onTap}) => Semantics(
              selected: selected,
              button: true,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? p.accent : p.inkMuted),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: context.text.titleSmall),
                        if (subtitle != null) Text(subtitle, style: context.text.bodySmall),
                      ]),
                    ),
                  ]),
                ),
              ),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          tile(
            title: 'Otomatik (önerilen)',
            subtitle: chosen == null && current != null ? 'Şu an: ${current.descriptionTr}' : 'Yüklü en kaliteli, çevrimdışı çalışan Almanca ses',
            selected: chosen == null,
            onTap: () => _choose(ref, null),
          ),
          for (var i = 0; i < voices.length; i++)
            tile(
              title: 'Ses ${i + 1}',
              subtitle: '${voices[i].descriptionTr}\n${voices[i].name}',
              selected: chosen == voices[i].name,
              onTap: () => _choose(ref, voices[i].name),
            ),
          const SizedBox(height: 4),
          Text('Bir sese dokununca seçilir ve örnek cümleyi okur. Sesler cihazın kendi sesleridir; anadil konuşmacısı kaydı değildir.',
              style: context.text.bodySmall),
          if (voices.length < 3) ...[
            const SizedBox(height: 6),
            Text('Daha fazla ses için (Android): Ayarlar → Erişilebilirlik → Metin okuma çıktısı → Google → Almanca ses verilerini indir.',
                style: context.text.bodySmall),
          ],
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerLeft, child: OutlinedButton.icon(onPressed: () => ref.read(speechServiceProvider).speak(_sample), icon: const Icon(Icons.volume_up_rounded), label: const Text('Örnek dinle'))),
        ]);
      },
    );
  }
}
