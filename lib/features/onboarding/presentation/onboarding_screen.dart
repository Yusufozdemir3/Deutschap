import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../../profile/domain/learner_profile.dart';

enum _Start { zero, placement, skip }

/// Short onboarding: only what changes the experience. Every step after
/// the first can be skipped and changed later in settings.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _page = PageController();
  final _name = TextEditingController();
  int _index = 0;
  Motivation? _motivation;
  final _interests = <String>{};
  int _minutes = 10;
  _Start _start = _Start.zero;
  bool _saving = false;

  static const _steps = 6;

  @override
  void dispose() {
    _page.dispose();
    _name.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < _steps - 1) {
      final reduce = MediaQuery.of(context).disableAnimations;
      _page.nextPage(duration: reduce ? const Duration(milliseconds: 1) : const Duration(milliseconds: 280), curve: Curves.easeOutCubic);
    } else {
      _finish();
    }
  }

  void _back() {
    if (_index > 0) _page.previousPage(duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic);
  }

  Future<void> _finish() async {
    if (_saving) return;
    setState(() => _saving = true);
    final name = _name.text.trim();
    await ref.read(profileProvider.notifier).edit((p) => p.copyWith(
          onboarded: true,
          name: name.isEmpty ? null : name,
          motivation: _motivation,
          interests: _interests,
          dailyMinutes: _minutes,
          startedFromZero: _start == _Start.zero,
        ));
    if (!mounted) return;
    if (_start == _Start.placement) {
      context.go('/onboarding/placement');
    } else {
      context.go('/heute');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: PageWidth(
          max: 560,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _index == 0 ? null : _back,
                      icon: const Icon(Icons.arrow_back_rounded),
                      tooltip: 'Geri',
                    ),
                    Expanded(
                      child: Semantics(
                        label: 'Adım ${_index + 1} / $_steps',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(value: (_index + 1) / _steps, minHeight: 6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: PageView(
                  controller: _page,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _index = i),
                  children: [
                    _welcome(context),
                    _step(context, 'Hikâyede sana nasıl seslenelim?', 'Karakterler seninle konuşurken bu adı kullanır. İstersen boş bırak.', [
                      TextField(
                        controller: _name,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(hintText: 'Adın (isteğe bağlı)'),
                        onSubmitted: (_) => _next(),
                      ),
                    ]),
                    _step(context, 'Neden Almanca öğreniyorsun?', 'Önerileri ve örnekleri buna göre seçeceğiz.', [
                      for (final m in Motivation.values)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ChoiceTile(label: m.labelTr, selected: _motivation == m, onTap: () => setState(() => _motivation = m)),
                        ),
                    ]),
                    _step(context, 'Neler ilgini çekiyor?', 'Birden fazla seçebilirsin. Ara sıra başka konulardan da bir şeyler göstereceğiz.', [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final e in interestTopics.entries)
                            FilterChip(
                              label: Text(e.value),
                              selected: _interests.contains(e.key),
                              onSelected: (v) => setState(() => v ? _interests.add(e.key) : _interests.remove(e.key)),
                            ),
                        ],
                      ),
                    ]),
                    _step(context, 'Günde ne kadar vaktin var?', 'Bu bir hedef değil, öneri boyutu. Her zaman istediğin kadar öğrenip istediğin an durabilirsin.', [
                      for (final m in const [5, 10, 15, 20])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _ChoiceTile(
                            label: '$m dakika',
                            sub: switch (m) { 5 => 'Kısa tekrar ve bir ifade', 10 => 'Bir ders ya da hikâye bölümü', 15 => 'Bölüm + alıştırma', _ => 'Okuma, konuşma ve tekrar' },
                            selected: _minutes == m,
                            onTap: () => setState(() => _minutes = m),
                          ),
                        ),
                    ]),
                    _step(context, 'Nereden başlayalım?', 'Bir test tüm becerilerini ölçemez; sadece başlangıç önerisi verir.', [
                      _ChoiceTile(label: 'Sıfırdan başlıyorum', sub: 'A1 yolunun başından', selected: _start == _Start.zero, onTap: () => setState(() => _start = _Start.zero)),
                      const SizedBox(height: 8),
                      _ChoiceTile(label: 'Biraz biliyorum', sub: '2 dakikalık kısa bir seviye denemesi', selected: _start == _Start.placement, onTap: () => setState(() => _start = _Start.placement)),
                      const SizedBox(height: 8),
                      _ChoiceTile(label: 'Testi atla', sub: 'A1 içeriğinde istediğim yerden başlarım', selected: _start == _Start.skip, onTap: () => setState(() => _start = _Start.skip)),
                      const SizedBox(height: 20),
                      Row(children: [
                        Icon(Icons.lock_outline_rounded, size: 18, color: p.inkMuted),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Hesap gerekmez. Öğrenme verilerin bu cihazda kalır; istediğin zaman dışa aktarabilir ya da silebilirsin.', style: context.text.bodySmall)),
                      ]),
                    ]),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _next,
                    child: Text(_index == 0 ? 'Başlayalım' : (_index == _steps - 1 ? 'Hazırım' : 'Devam')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _welcome(BuildContext context) {
    final p = context.palette;
    Widget pillar(IconData icon, String title, String body) => Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: p.accentSoft, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: p.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: context.text.titleMedium),
                const SizedBox(height: 2),
                Text(body, style: context.text.bodyMedium!.copyWith(color: p.inkMuted)),
              ]),
            ),
          ]),
        );
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 16),
      children: [
        Text('Deutschap', style: context.text.displaySmall!.copyWith(fontFamily: context.serif)),
        const SizedBox(height: 10),
        Text('Hikâyelerle keşfet, kalıcı bir kelime hazinesi biriktir, öğrendiğini gerçek konuşmalarda kullan.', style: context.text.titleMedium!.copyWith(color: p.inkMuted).regular),
        const SizedBox(height: 36),
        pillar(Icons.menu_book_rounded, 'Bağlantılı hikâyeler', 'Berlin\'de yeni bir hayat. Her kelimeye dokun, anlamını ve kullanımını gör.'),
        pillar(Icons.bookmarks_rounded, 'Senin kelime hazinen', 'Kaydettiğin her kelime nerede karşılaştığını hatırlar ve doğru zamanda geri gelir.'),
        pillar(Icons.forum_rounded, 'Gerçek durumlar', 'Fırında, kafede, telefonda… Önce anlaşılmak, sonra düzeltme.'),
      ],
    );
  }

  Widget _step(BuildContext context, String title, String subtitle, List<Widget> children) => ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
        children: [
          Text(title, style: context.text.headlineSmall),
          const SizedBox(height: 8),
          Text(subtitle, style: context.text.bodyMedium!.copyWith(color: context.palette.inkMuted)),
          const SizedBox(height: 24),
          ...children,
        ],
      );
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({required this.label, required this.selected, required this.onTap, this.sub});
  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      selected: selected,
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        color: selected ? p.accentSoft : null,
        borderColor: selected ? p.accent : null,
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: context.text.titleSmall),
              if (sub != null) Text(sub!, style: context.text.bodySmall),
            ]),
          ),
          Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: selected ? p.accent : p.inkMuted),
        ]),
      ),
    );
  }
}
