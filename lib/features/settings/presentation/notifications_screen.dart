import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../../profile/domain/learner_profile.dart';

/// Every category is opt-in and off by default. v0.1 stores the choices;
/// delivery is not implemented yet and the screen says so.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(profileProvider).valueOrNull?.notifications ?? const NotificationPrefs();
    final notifier = ref.read(profileProvider.notifier);
    void set(NotificationPrefs v) => notifier.edit((p) => p.copyWith(notifications: v));
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Bildirimler')),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(14)),
                child: Text('Bu sürüm henüz bildirim göndermiyor. Seçimlerin kaydedilir ve bildirimler geldiğinde uygulanır. O zaman da izin, ancak bir hatırlatıcıyı açtığında istenecek.', style: context.text.bodyMedium),
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Çalışma hatırlatıcısı'),
                    subtitle: Text('Kendi seçtiğin saatte, günde en fazla bir kez · ${n.reminderHour.toString().padLeft(2, '0')}:00'),
                    value: n.studyReminder,
                    onChanged: (v) => set(n.copyWith(studyReminder: v)),
                  ),
                  if (n.studyReminder)
                    Slider(
                      value: n.reminderHour.toDouble(),
                      min: 6,
                      max: 22,
                      divisions: 16,
                      label: '${n.reminderHour}:00',
                      onChanged: (v) => set(n.copyWith(reminderHour: v.round())),
                    ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tekrar zamanı gelen kelimeler'),
                    subtitle: const Text('Sadece birikmiş tekrar varsa.'),
                    value: n.reviewDue,
                    onChanged: (v) => set(n.copyWith(reviewDue: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Takip ettiğin hikâyede yeni bölüm'),
                    value: n.newEpisodes,
                    onChanged: (v) => set(n.copyWith(newEpisodes: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Haftalık özet'),
                    value: n.weeklySummary,
                    onChanged: (v) => set(n.copyWith(weeklySummary: v)),
                  ),
                ]),
              ),
              const SectionTitle('Sessiz saatler'),
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${n.quietFrom}:00 – ${n.quietTo}:00 arası hiçbir bildirim gönderilmez.', style: context.text.bodyMedium),
                  RangeSlider(
                    values: RangeValues(n.quietTo.toDouble(), n.quietFrom.toDouble()),
                    min: 0,
                    max: 24,
                    divisions: 24,
                    labels: RangeLabels('${n.quietTo}:00', '${n.quietFrom}:00'),
                    onChanged: (r) => set(n.copyWith(quietTo: r.start.round(), quietFrom: r.end.round())),
                  ),
                  Text('Kaydırıcı: sol uç sabah bitiş, sağ uç akşam başlangıç.', style: context.text.bodySmall),
                ]),
              ),
              const SizedBox(height: 16),
              Text('Bildirimlerde kilit ekranında öğrenme ayrıntıları gösterilmeyecek; "ilerlemeni kaybediyorsun" gibi mesajlar hiç kullanılmayacak.', style: context.text.bodySmall),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => set(const NotificationPrefs()),
                child: const Text('Hepsini kapat'),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}
