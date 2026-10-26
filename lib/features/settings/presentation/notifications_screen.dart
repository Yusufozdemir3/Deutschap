import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../../notifications/application/notification_providers.dart';
import '../../profile/domain/learner_profile.dart';

/// Every category is opt-in and off by default. Permission is asked the
/// first time a reminder is turned on, not before.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  static const _weekdays = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(profileProvider).valueOrNull?.notifications ?? const NotificationPrefs();
    final notifier = ref.read(profileProvider.notifier);
    final service = ref.watch(notificationServiceProvider);
    final next = ref.watch(notificationSyncProvider).valueOrNull ?? const [];
    Future<void> set(NotificationPrefs v) async {
      final turningOn = v.anyEnabled && !n.anyEnabled;
      if (turningOn && service.supported && !await service.requestPermission()) {
        if (context.mounted) showToast(context, 'Bildirim izni verilmedi. İstersen sistem ayarlarından açabilirsin.');
        return;
      }
      await notifier.edit((p) => p.copyWith(notifications: v));
    }

    final p = context.palette;
    final String banner;
    if (!service.supported) {
      banner = 'Bildirimler sadece Android ve iOS uygulamasında gönderilir. Burada seçimlerin kaydedilir.';
    } else if (!n.anyEnabled) {
      banner = 'Hepsi kapalı. Birini açtığında bildirim izni istenir.';
    } else if (next.isEmpty) {
      banner = 'Önümüzdeki günlerde gönderilecek bildirim yok.';
    } else {
      final t = next.first.at;
      banner = 'Sıradaki: ${_weekdays[t.weekday - 1]} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} · Bugün zaten çalıştıysan o günün hatırlatması gelmez.';
    }
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
                child: Text(banner, style: context.text.bodyMedium),
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
                    subtitle: const Text('Sadece birikmiş tekrar varsa, hatırlatıcı saatinde.'),
                    value: n.reviewDue,
                    onChanged: (v) => set(n.copyWith(reviewDue: v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Takip ettiğin hikâyede yeni bölüm'),
                    subtitle: const Text('İçerik güncellemeleri yayımlanmaya başlayınca.'),
                    value: n.newEpisodes,
                    onChanged: null,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Haftalık özet'),
                    subtitle: const Text('Pazar akşamı, haftalık hedefine göre.'),
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
