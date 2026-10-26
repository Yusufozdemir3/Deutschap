import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../../account/presentation/account_card.dart';
import 'backup_actions.dart';
import 'content_update_card.dart';
import '../../profile/domain/learner_profile.dart';
import 'voice_picker.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull ?? const LearnerProfile();
    final notifier = ref.read(profileProvider.notifier);
    final content = ref.watch(contentProvider);
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Ayarlar')),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const AccountCard(),
              const SectionTitle('Öğrenme', padding: EdgeInsets.fromLTRB(2, 16, 2, 10)),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Adın (hikâyelerde)'),
                    subtitle: Text(profile.name ?? 'Belirtilmedi'),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: () async {
                      final c = TextEditingController(text: profile.name ?? '');
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (d) => AlertDialog(
                          title: const Text('Adın'),
                          content: TextField(controller: c, autofocus: true),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
                            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Kaydet')),
                          ],
                        ),
                      );
                      if (ok == true) await notifier.edit((p) => LearnerProfile.fromJson({...p.toJson(), 'name': c.text.trim().isEmpty ? null : c.text.trim()}));
                    },
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text('Günlük öneri süresi', style: context.text.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 5, label: Text('5 dk')),
                      ButtonSegment(value: 10, label: Text('10')),
                      ButtonSegment(value: 15, label: Text('15')),
                      ButtonSegment(value: 20, label: Text('20')),
                    ],
                    selected: {profile.dailyMinutes},
                    onSelectionChanged: (s) => notifier.edit((p) => p.copyWith(dailyMinutes: s.first)),
                  ),
                  const SizedBox(height: 16),
                  Text('Haftalık hedef: ${profile.weeklyGoalDays} gün', style: context.text.titleSmall),
                  Slider(
                    value: profile.weeklyGoalDays.toDouble(),
                    min: 1,
                    max: 7,
                    divisions: 6,
                    label: '${profile.weeklyGoalDays} gün',
                    onChanged: (v) => notifier.edit((p) => p.copyWith(weeklyGoalDays: v.round())),
                  ),
                  Text('Esnek bir hedef. Kaçırılan günler hiçbir şeyi sıfırlamaz.', style: context.text.bodySmall),
                  const SizedBox(height: 16),
                  Text('Görünüm', style: context.text.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'system', label: Text('Sistem')),
                      ButtonSegment(value: 'light', label: Text('Açık')),
                      ButtonSegment(value: 'dark', label: Text('Koyu')),
                    ],
                    selected: {profile.themeMode},
                    onSelectionChanged: (s) => notifier.edit((p) => p.copyWith(themeMode: s.first)),
                  ),
                  const SizedBox(height: 12),
                  Text('Yazı boyutu', style: context.text.bodyMedium),
                  Slider(
                    value: profile.textScale,
                    min: 0.9,
                    max: 1.4,
                    divisions: 5,
                    label: '%${(profile.textScale * 100).round()}',
                    onChanged: (v) => notifier.edit((p) => p.copyWith(textScale: double.parse(v.toStringAsFixed(2)))),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Okunaklı yazı tipi'),
                    subtitle: const Text('Atkinson Hyperlegible: harfleri birbirinden kolay ayırt edilir; disleksi ve az görme için tasarlandı.'),
                    value: profile.readableFont,
                    onChanged: (v) => notifier.edit((p) => p.copyWith(readableFont: v)),
                  ),
                  const Divider(height: 28),
                  const ContentUpdateCard(),
                  const Divider(height: 28),
                  Text('Hikâyelerin dil seviyesi', style: context.text.titleSmall),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [ButtonSegment(value: 'A1', label: Text('A1')), ButtonSegment(value: 'A2', label: Text('A2')), ButtonSegment(value: 'B1', label: Text('B1'))],
                    selected: {profile.level},
                    onSelectionChanged: (s) => notifier.edit((p) => p.copyWith(level: s.first)),
                  ),
                  const SizedBox(height: 4),
                  Text('Aynı hikâye, aynı karakterler: üst seviyelerde cümleler daha uzun ve doğal. 6–10. bölümler A2, 11. bölümden sonrası (ikinci sezon) B1 düzeyinde; seviyenin üstündeki bölümler ana sayfada önerilmez ama hikâye listesinden açılır.', style: context.text.bodySmall),
                  const Divider(height: 28),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('İngilizce anlamları da göster'),
                    value: profile.showEnglish,
                    onChanged: (v) => notifier.edit((p) => p.copyWith(showEnglish: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ayrıntılı geri bildirim'),
                    subtitle: const Text('Konuşmalarda her mesaj için birden fazla düzeltme göster.'),
                    value: profile.detailedFeedback,
                    onChanged: (v) => notifier.edit((p) => p.copyWith(detailedFeedback: v)),
                  ),
                  const SizedBox(height: 8),
                  Text('Konuşma hızı (ses)', style: context.text.titleSmall),
                  Slider(
                    value: profile.speechRate,
                    min: 0.25,
                    max: 0.65,
                    divisions: 8,
                    label: profile.speechRate.toStringAsFixed(2),
                    onChanged: (v) => notifier.edit((p) => p.copyWith(speechRate: v)),
                  ),
                  const Divider(height: 28),
                  Text('Almanca ses', style: context.text.titleSmall),
                  const SizedBox(height: 4),
                  const VoicePicker(),
                ]),
              ),
              const SectionTitle('İlgi alanları'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in interestTopics.entries)
                  FilterChip(
                    label: Text(e.value),
                    selected: profile.interests.contains(e.key),
                    onSelected: (v) => notifier.edit((p) => p.copyWith(interests: v ? {...p.interests, e.key} : ({...p.interests}..remove(e.key)))),
                  ),
              ]),
              if (profile.hiddenTopics.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text('Gizlenen konular: ${profile.hiddenTopics.map((t) => interestTopics[t] ?? t).join(', ')}', style: context.text.bodySmall),
                TextButton(onPressed: () => notifier.edit((p) => p.copyWith(hiddenTopics: {})), child: const Text('Gizlenen konuları geri getir')),
              ],
              const SectionTitle('Bildirimler'),
              AppCard(
                onTap: () => context.push('/settings/notifications'),
                child: Row(children: [
                  const Icon(Icons.notifications_none_rounded),
                  const SizedBox(width: 12),
                  Expanded(child: Text(profile.notifications.anyEnabled ? 'Bazı hatırlatıcılar seçili' : 'Tüm bildirimler kapalı')),
                  const Icon(Icons.chevron_right_rounded),
                ]),
              ),
              const SectionTitle('Gizlilik'),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Konuşma metinlerini sakla'),
                    subtitle: const Text('Kapalıyken yalnızca hedefler ve düzeltmeler saklanır, konuşmanın tamamı saklanmaz.'),
                    value: profile.keepTranscripts,
                    onChanged: (v) => notifier.edit((p) => p.copyWith(keepTranscripts: v)),
                  ),
                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Kişiselleştirme sinyallerini sıfırla'),
                    subtitle: const Text('"Sık tekrarlanan zorluklar" ve alıştırma geçmişi silinir. Kelimelerin ve ilerlemen kalır.'),
                    onTap: () async {
                      if (!await confirm(context, title: 'Sıfırlansın mı?', message: 'Konuşma geçmişi ve alıştırma denemeleri silinecek. Kelimelerin ve tamamlanan dersler kalır.', confirmLabel: 'Sıfırla')) return;
                      await ref.read(dataRepositoryProvider).resetLearningSignals();
                      ref.bumpData();
                      if (context.mounted) showToast(context, 'Sıfırlandı');
                    },
                  ),
                  const SizedBox(height: 4),
                  Text('Hesap açıp eşitlemeyi açmadıkça hiçbir öğrenme verin cihaz dışına gönderilmez. Analitik ya da reklam takibi yok.', style: context.text.bodySmall),
                ]),
              ),
              const SectionTitle('Verilerin'),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const BackupCard(),
                  const Divider(height: 28),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final json = await ref.read(dataRepositoryProvider).exportJson();
                      await Clipboard.setData(ClipboardData(text: json));
                      if (context.mounted) showToast(context, 'Tüm verilerin JSON olarak panoya kopyalandı (${(json.length / 1024).toStringAsFixed(1)} KB)');
                    },
                    icon: const Icon(Icons.data_object_rounded),
                    label: const Text('Tüm verileri dışa aktar (JSON)'),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final tsv = await ref.read(dataRepositoryProvider).exportVocabularyTsv();
                      await Clipboard.setData(ClipboardData(text: tsv));
                      if (context.mounted) showToast(context, 'Kelime listesi panoya kopyalandı (sekmeyle ayrılmış, tablo programlarına yapıştırılabilir)');
                    },
                    icon: const Icon(Icons.table_view_outlined),
                    label: const Text('Kelimeleri dışa aktar (tablo)'),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(foregroundColor: context.palette.danger),
                    onPressed: () => _deleteAll(context, ref),
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const Text('Bu cihazdaki tüm verilerimi sil'),
                  ),
                ]),
              ),
              const SectionTitle('Hakkında'),
              AppCard(
                onTap: () => context.push('/content-review'),
                child: Row(children: [
                  const Icon(Icons.fact_check_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('İçerik denetimi'),
                      Text('Almanca bilenler için: cümleleri kontrol et, hataları işaretle.', style: context.text.bodySmall),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ]),
              ),
              const SizedBox(height: 12),
              Text('Deutschap 0.4 · içerik sürümü ${content.version}', style: context.text.bodySmall),
              Text('Yazı tipleri: Manrope, Literata (SIL Open Font License).', style: context.text.bodySmall),
            ]),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setState) => AlertDialog(
          title: const Text('Tüm veriler silinsin mi?'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Kelimelerin, notların, koleksiyonların, ilerlemen ve kendi metinlerin bu cihazdan kalıcı olarak silinir. Geri alınamaz. İstersen önce dışa aktar.'),
            const SizedBox(height: 12),
            const Text('Onaylamak için SİL yaz:'),
            TextField(controller: c, autofocus: true, onChanged: (_) => setState(() {})),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Vazgeç')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: d.palette.danger),
              onPressed: c.text.trim().toUpperCase() == 'SİL' || c.text.trim().toUpperCase() == 'SIL' ? () => Navigator.pop(d, true) : null,
              child: const Text('Kalıcı olarak sil'),
            ),
          ],
        ),
      ),
    );
    c.dispose();
    if (ok != true) return;
    await ref.read(dataRepositoryProvider).deleteAll();
    ref.bumpData();
    await ref.read(profileProvider.notifier).reload();
    if (context.mounted) context.go('/onboarding');
  }
}
