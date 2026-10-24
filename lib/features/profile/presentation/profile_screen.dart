import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../../progress/application/progress_providers.dart';
import '../../vocabulary/application/vocab_providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider).valueOrNull;
    final stats = ref.watch(statsProvider).valueOrNull;
    final words = ref.watch(vocabCountProvider).valueOrNull ?? 0;
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Profil')),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: p.accentSoft,
                  child: Text((profile?.name?.isNotEmpty ?? false) ? profile!.name!.characters.first.toUpperCase() : 'D', style: context.text.titleLarge!.copyWith(color: p.accent)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(profile?.name ?? 'Öğrenci', style: context.text.titleLarge),
                    Text(profile?.motivation?.labelTr ?? 'Almanca öğreniyor', style: context.text.bodySmall),
                  ]),
                ),
              ]),
              const SizedBox(height: 20),
              AppCard(
                onTap: () => context.push('/progress'),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Gelişimin', style: context.text.titleMedium),
                      const SizedBox(height: 4),
                      Text('$words kelime · ${stats?.lessonsCompleted ?? 0} ders · ${stats?.episodesCompleted ?? 0} bölüm · ${stats?.scenariosCompleted ?? 0} durum', style: context.text.bodySmall),
                    ]),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ]),
              ),
              const SizedBox(height: 16),
              _tile(context, Icons.tune_rounded, 'Ayarlar', 'Öğrenme tercihleri, ses, geri bildirim', () => context.push('/settings')),
              _tile(context, Icons.notifications_none_rounded, 'Bildirimler', 'Hatırlatıcı tercihleri', () => context.push('/settings/notifications')),
              _tile(context, Icons.collections_bookmark_outlined, 'Koleksiyonlar', 'Kelimelerini grupla', () => context.push('/collections')),
              _tile(context, Icons.info_outline_rounded, 'Bu sürüm hakkında', 'Neler var, neler henüz yok', () => showAboutSheet(context)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, IconData icon, String title, String sub, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: AppCard(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(children: [
            Icon(icon),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: context.text.titleSmall),
                Text(sub, style: context.text.bodySmall),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded),
          ]),
        ),
      );
}

void showAboutSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (c) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        builder: (c, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
          children: [
            Text('Deutschap 0.1', style: c.text.headlineSmall),
            const SizedBox(height: 8),
            Text('İlk sürüm: A1 seviyesinde, çevrimdışı çalışan bir temel.', style: c.text.bodyMedium),
            const SectionTitle('Neler var'),
            for (final s in const [
              '12 ünite / 24 ders: A1 yolunun tamamı',
              '"Neu in Berlin" hikâye serisi: 4 bağlantılı bölüm',
              'Kelime defteri: bağlam, koleksiyonlar, aralıklı tekrar',
              '5 gerçek hayat senaryosu (kural tabanlı, çevrimdışı)',
              'Okuma: hazır metinler ve kendi metnin',
              'Cihazın metin-okuma sesiyle telaffuz',
            ])
              Text('• $s', style: c.text.bodyMedium),
            const SectionTitle('Henüz yok / sınırlamalar'),
            for (final s in const [
              'Yapay zekâ destekli sohbet ve öğretmen: güvenli bir sunucu kurulana kadar kapalı. Konuşma ortağı şimdilik kurala dayalı.',
              'Konuşma tanıma ve telaffuz puanlama yok. Sesler cihazın sentez sesidir, anadil konuşmacısı kaydı değil.',
              'Bildirimler: tercihlerin kaydedilir ama bu sürüm henüz bildirim göndermez.',
              'Hesap ve cihazlar arası eşitleme yok; veriler sadece bu cihazda.',
              'İçerik otomatik kontrollerden geçti ama henüz bir Almanca öğretmeni tarafından gözden geçirilmedi.',
              'PDF/EPUB içe aktarma yok; metin yapıştırabilirsin.',
            ])
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('• $s', style: c.text.bodyMedium)),
          ],
        ),
      ),
    );
