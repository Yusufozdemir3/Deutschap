import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../ui/widgets.dart';
import '../../profile/domain/learner_profile.dart';

class _Q {
  const _Q(this.skill, this.prompt, this.options, this.answer, {this.de});
  final String skill;
  final String prompt;
  final String? de;
  final List<String> options;
  final int answer;
}

const _questions = [
  _Q('vocabulary', '"die Rechnung" ne demek?', ['hesap / fatura', 'mutfak', 'randevu'], 0),
  _Q('vocabulary', '"Ich habe keine Zeit." ne demek?', ['Saatim yok.', 'Vaktim yok.', 'Hiç zamanım oldu.'], 1),
  _Q('vocabulary', '"randevu" Almanca hangisi?', ['der Termin', 'die Anmeldung', 'das Formular'], 0),
  _Q('grammar', 'Boşluğa ne gelir?', ['heiße', 'heißt', 'heißen'], 0, de: 'Ich ___ Deniz.'),
  _Q('grammar', 'Boşluğa ne gelir?', ['ein', 'einen', 'eine'], 1, de: 'Ich möchte ___ Kaffee.'),
  _Q('grammar', 'Hangisi doğru?', ['Heute ich gehe ins Café.', 'Heute gehe ich ins Café.', 'Heute ins Café gehe ich.'], 1),
  _Q('reading', 'Lina nereden geliyor?', ['Berlin', 'Leipzig', 'Hamburg'], 1, de: 'Lina wohnt in Berlin, aber sie kommt aus Leipzig.'),
  _Q('reading', 'Randevu ne zaman?', ['Salı 10:30', 'Salı 9:30', 'Perşembe 9:30'], 1, de: 'Der Termin ist am Dienstag um halb zehn.'),
  _Q('reading', 'Fırın pazar günü ne zaman açık?', ['Bütün gün', 'Sadece sabah', 'Hiç açık değil'], 1, de: 'Am Sonntag ist die Bäckerei nur am Morgen offen.'),
];

/// Asked only after a very strong A1 round.
const _a2Questions = [
  _Q('grammar', 'Hangisi doğru?', ['Ich habe gestern nach Hamburg gefahren.', 'Ich bin gestern nach Hamburg gefahren.', 'Ich bin gestern nach Hamburg fahren.'], 1),
  _Q('grammar', 'Boşluğa ne gelir?', ['ich müde bin', 'bin ich müde', 'ich bin müde'], 0, de: 'Ich bleibe zu Hause, weil ___.'),
  _Q('grammar', 'Boşluğa ne gelir?', ['mich', 'mir', 'ich'], 1, de: 'Kannst du ___ bitte helfen?'),
  _Q('reading', 'Aylin neden geç kaldı?', ['Otobüs rötar yaptı', 'Uyuyakaldı', 'Hasta oldu'], 0, de: 'Aylin kam zu spät, weil der Bus Verspätung hatte. Deshalb musste sie die nächste Stunde warten.'),
];

/// A short, optional placement. It produces separate rough estimates per
/// skill and a suggested starting point, never a single "level".
class PlacementScreen extends ConsumerStatefulWidget {
  const PlacementScreen({super.key});
  @override
  ConsumerState<PlacementScreen> createState() => _PlacementScreenState();
}

class _PlacementScreenState extends ConsumerState<PlacementScreen> {
  int _i = 0;
  int? _picked;
  final _correct = <String, int>{};
  var _a2 = false;
  int _a2Correct = 0;

  List<_Q> get _all => [..._questions, if (_a2) ..._a2Questions];
  bool get _done => _i >= _all.length;

  void _answer(int i) {
    if (_picked != null) return;
    setState(() {
      _picked = i;
      final q = _all[_i];
      if (i == q.answer) {
        if (_i < _questions.length) {
          _correct[q.skill] = (_correct[q.skill] ?? 0) + 1;
        } else {
          _a2Correct++;
        }
      }
    });
    Future.delayed(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _i++;
          _picked = null;
          // Only a very strong A1 round opens the short A2 round.
          if (_i == _questions.length && _correct.values.fold<int>(0, (a, b) => a + b) >= 8) _a2 = true;
        });
      }
    });
  }

  String _estimate(String skill) => switch (_correct[skill] ?? 0) { 0 || 1 => 'A0', 2 => 'A1', _ => 'A1+' };

  Future<void> _save({required String route}) async {
    final router = GoRouter.of(context);
    final a2 = _a2 && _a2Correct >= 3;
    await ref.read(profileProvider.notifier).edit((p) => p.copyWith(
          skills: SkillEstimates(vocabulary: _estimate('vocabulary'), grammar: _estimate('grammar'), reading: _estimate('reading')),
          startedFromZero: false,
          level: a2 ? 'A2' : null,
        ));
    router.go('/heute');
    if (route != '/heute') unawaited(router.push(route));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kısa seviye denemesi'),
        actions: [if (!_done) TextButton(onPressed: () => context.go('/heute'), child: const Text('Atla'))],
      ),
      body: SafeArea(child: PageWidth(max: 560, child: _done ? _result(context) : _question(context))),
    );
  }

  Widget _question(BuildContext context) {
    final q = _all[_i];
    final p = context.palette;
    return ListView(
      padding: pagePadding,
      children: [
        LinearProgressIndicator(value: _i / _all.length),
        const SizedBox(height: 24),
        Text(_i >= _questions.length ? 'A2 sorusu ${_i - _questions.length + 1} / ${_a2Questions.length}' : '${_i + 1} / ${_all.length}', style: context.text.labelSmall),
        const SizedBox(height: 8),
        if (q.de != null) ...[
          AppCard(child: Text(q.de!, style: context.reading)),
          const SizedBox(height: 16),
        ],
        Text(q.prompt, style: context.text.titleMedium),
        const SizedBox(height: 16),
        for (var k = 0; k < q.options.length; k++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AppCard(
              onTap: () => _answer(k),
              color: _picked == null ? null : (k == q.answer ? p.successSoft : (k == _picked ? p.dangerSoft : null)),
              child: Text(q.options[k], style: context.text.bodyLarge),
            ),
          ),
        const SizedBox(height: 8),
        Text('Bilmiyorsan tahmin etmene gerek yok – "Atla" da olur.', style: context.text.bodySmall),
      ],
    );
  }

  Widget _result(BuildContext context) {
    final total = _correct.values.fold<int>(0, (a, b) => a + b);
    final strong = total >= 7;
    final a2 = _a2 && _a2Correct >= 3;
    Widget row(String label, String skill) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Text(label, style: context.text.bodyLarge)),
            Pill(_estimate(skill)),
          ]),
        );
    return ListView(
      padding: pagePadding,
      children: [
        Text('Başlangıç tahminin', style: context.text.headlineSmall),
        const SizedBox(height: 8),
        Text('Bu sonuçlar kaba bir başlangıç noktasıdır, ölçüm değildir. Öğrendikçe gerçek performansına göre güncellenir.', style: context.text.bodyMedium),
        const SizedBox(height: 20),
        AppCard(
          child: Column(children: [
            row('Kelime bilgisi', 'vocabulary'),
            row('Dil bilgisi', 'grammar'),
            row('Okuma', 'reading'),
            const Divider(height: 24),
            Row(children: [
              Expanded(child: Text('Dinleme ve konuşma', style: context.text.bodyLarge)),
              Text('henüz ölçülmedi', style: context.text.bodySmall),
            ]),
          ]),
        ),
        const SizedBox(height: 20),
        Text(a2 ? 'Önerimiz: A1 temelin sağlam görünüyor. A2 yolundan başlayabilirsin; hikâyeler de A2 sürümüyle açılır. Önceki dersler her zaman açık.' : strong ? 'Önerimiz: temel selamlaşmaları biliyorsun. "Kafede sipariş" ünitesinden başlayabilirsin; istersen önceki dersler hep açık.' : 'Önerimiz: A1 yolunun başından başla. Bildiğin yerleri hızlıca geçersin.',
            style: context.text.bodyLarge),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: () => _save(route: a2 ? '/lesson/a2u1l1' : (strong ? '/lesson/u4l1' : '/lesson/u1l1')),
            child: Text(a2 ? 'A2 yoluna başla' : (strong ? 'Kafede sipariş dersine git' : 'İlk derse başla'))),
        const SizedBox(height: 8),
        OutlinedButton(onPressed: () => _save(route: '/heute'), child: const Text('Ana sayfaya git')),
      ],
    );
  }
}
