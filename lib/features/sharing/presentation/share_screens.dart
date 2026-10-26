import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../content/models/lexeme.dart';
import '../../../learning/text/tokenizer.dart';
import '../../../ui/widgets.dart';
import '../application/pack_service.dart';
import '../domain/word_pack.dart';

/// Shows a pack as a QR code and a copyable code / link.
class SharePackScreen extends StatelessWidget {
  const SharePackScreen({super.key, required this.pack});
  final WordPack pack;

  /// Codes above this length make QR codes too dense to scan reliably.
  static const _qrLimit = 1800;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final link = pack.link;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Paylaş')),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(pack.name, style: context.text.headlineSmall, textAlign: TextAlign.center),
              Text('${pack.size} kelime${pack.teacher ? ' · öğretmen paketi' : ''}', style: context.text.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              if (link.length <= _qrLimit)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                    child: QrImageView(data: link, size: 240, backgroundColor: Colors.white, semanticsLabel: 'Paylaşım QR kodu'),
                  ),
                )
              else
                const FeedbackPanel(positive: true, neutral: true, title: 'QR için çok uzun', body: 'Bu liste QR koduna sığmıyor. Kodu kopyalayıp mesajla gönder.'),
              const SizedBox(height: 12),
              Text('Arkadaşın telefonunun kamerasıyla QR kodu okutunca Deutschap açılır (Android). '
                  'Ya da kodu kopyalayıp mesajla gönder; karşı taraf Koleksiyonlar → İçe aktar ile yapıştırır. '
                  'Paylaşılan sadece kelimelerdir; ilerlemen ve notların paylaşılmaz.', style: context.text.bodySmall),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: 'Deutschap kelime listesi "${pack.name}" (${pack.size} kelime):\n${pack.encode()}'));
                  if (context.mounted) showToast(context, 'Kod panoya kopyalandı');
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Kodu kopyala'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (context.mounted) showToast(context, 'Bağlantı panoya kopyalandı');
                },
                icon: const Icon(Icons.link_rounded),
                label: const Text('Bağlantıyı kopyala'),
              ),
              const SizedBox(height: 16),
              Text('Kod: ${pack.encode().length} karakter', style: context.text.labelSmall!.copyWith(color: p.inkMuted), textAlign: TextAlign.center),
            ]),
          ),
        ],
      ),
    );
  }
}

/// Paste or open a pack code, preview it and add it to the library.
class ImportPackScreen extends ConsumerStatefulWidget {
  const ImportPackScreen({super.key, this.initialCode});
  final String? initialCode;
  @override
  ConsumerState<ImportPackScreen> createState() => _ImportPackScreenState();
}

class _ImportPackScreenState extends ConsumerState<ImportPackScreen> {
  late final _input = TextEditingController(text: widget.initialCode == null ? '' : '${WordPack.prefix}${widget.initialCode!.replaceFirst(WordPack.prefix, '')}');
  WordPack? _pack;
  PackImport? _result;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pack = WordPack.decode(_input.text);
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    final r = await importPack(_pack!, repo: ref.read(vocabRepositoryProvider), lexicon: ref.read(contentProvider).lexicon);
    ref.bumpData();
    if (mounted) {
      setState(() {
        _busy = false;
        _result = r;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final lexicon = ref.watch(contentProvider).lexicon;
    final pack = _pack;
    final result = _result;
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Kelime listesi içe aktar')),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (result == null) ...[
                Text('Bir arkadaşının ya da öğretmeninin gönderdiği kodu yapıştır (DSP1: ile başlar). Bütün mesajı yapıştırman da olur.', style: context.text.bodySmall),
                const SizedBox(height: 10),
                TextField(
                  controller: _input,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: 'DSP1:…'),
                  onChanged: (v) => setState(() => _pack = WordPack.decode(v)),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () async {
                      final data = await Clipboard.getData(Clipboard.kTextPlain);
                      if (data?.text == null) return;
                      _input.text = data!.text!;
                      setState(() => _pack = WordPack.decode(data.text!));
                    },
                    icon: const Icon(Icons.content_paste_rounded),
                    label: const Text('Panodan yapıştır'),
                  ),
                ),
                if (_input.text.trim().isNotEmpty && pack == null)
                  const FeedbackPanel(positive: false, title: 'Geçerli bir kod bulunamadı', body: 'Kodun tamamını kopyaladığından emin ol.'),
                if (pack != null) ...[
                  const SizedBox(height: 8),
                  AppCard(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if (pack.teacher) Pill('Öğretmen paketi', icon: Icons.school_outlined, color: context.palette.accentSoft),
                      const SizedBox(height: 4),
                      Text(pack.name, style: context.text.titleLarge),
                      Text('${pack.size} kelime', style: context.text.bodySmall),
                      if (pack.note != null) ...[const SizedBox(height: 6), Text(pack.note!, style: context.text.bodyMedium)],
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final id in pack.lexemeIds.take(24))
                          if (lexicon.byId(id) case final l?) Tag(l.headword),
                        for (final c in pack.custom.take(12)) Tag(c.headword, icon: Icons.edit_note_rounded),
                        if (pack.size > 36) Tag('+${pack.size - 36}'),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _import,
                    icon: const Icon(Icons.download_done_rounded),
                    label: const Text('Kelime defterime ekle'),
                  ),
                  const SizedBox(height: 4),
                  Text('Kelimeler yeni bir koleksiyonda toplanır ve tekrar planına girer. Zaten kayıtlı olanlar tekrar eklenmez.', style: context.text.bodySmall),
                ],
              ] else ...[
                const SizedBox(height: 12),
                Icon(Icons.check_circle_rounded, size: 56, color: context.palette.success),
                const SizedBox(height: 8),
                Text('"${pack!.name}" eklendi', style: context.text.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text(
                  [
                    '${result.added} yeni kelime',
                    if (result.alreadySaved > 0) '${result.alreadySaved} zaten kayıtlıydı',
                    if (result.unknown > 0) '${result.unknown} kelime bu sürümde yok (uygulamayı güncelle)',
                  ].join(' · '),
                  style: context.text.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => context.pushReplacement('/drill/run?src=${Uri.encodeComponent('collection:${result.collectionId}')}&mode=mixed&n=10'),
                  icon: const Icon(Icons.fitness_center_rounded),
                  label: const Text('Hemen alıştır'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: () => context.pushReplacement('/collections'), child: const Text('Koleksiyonlara git')),
              ],
            ]),
          ),
        ],
      ),
    );
  }
}

/// Teacher mode: build a word pack from dictionary words and own words,
/// then share it with a class as a QR code or a code.
class TeacherPackScreen extends ConsumerStatefulWidget {
  const TeacherPackScreen({super.key});
  @override
  ConsumerState<TeacherPackScreen> createState() => _TeacherPackScreenState();
}

class _TeacherPackScreenState extends ConsumerState<TeacherPackScreen> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  final _search = TextEditingController();
  final _customDe = TextEditingController();
  final _customTr = TextEditingController();
  final _customEx = TextEditingController();
  final _ids = <String>[];
  final _custom = <CustomWord>[];

  @override
  void dispose() {
    for (final c in [_name, _note, _search, _customDe, _customTr, _customEx]) {
      c.dispose();
    }
    super.dispose();
  }

  List<Lexeme> _matches() {
    final q = fold(_search.text.trim());
    if (q.length < 2) return const [];
    return [
      for (final l in ref.read(contentProvider).lexicon.all)
        if (!_ids.contains(l.id) && (fold(l.lemma).contains(q) || fold(l.tr).contains(q))) l,
    ].take(8).toList();
  }

  void _addTopic(String level) {
    final words = ref.read(contentProvider).lexicon.all.where((l) => l.cefr == level).map((l) => l.id);
    setState(() => _ids.addAll(words.where((id) => !_ids.contains(id)).take(30 - _ids.length.clamp(0, 30))));
  }

  @override
  Widget build(BuildContext context) {
    final lexicon = ref.watch(contentProvider).lexicon;
    final matches = _matches();
    final ready = _name.text.trim().isNotEmpty && (_ids.isNotEmpty || _custom.isNotEmpty);
    final units = [for (final p in ref.watch(contentProvider).paths) for (final u in p.units) if (u.lessons.isNotEmpty) (p.level, u)];
    return Scaffold(
      appBar: AppBar(leading: const BackOrHomeButton(), title: const Text('Öğretmen modu')),
      body: ListView(
        padding: pagePadding,
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Sınıfın için bir kelime paketi hazırla ve QR kodla ya da kodla paylaş. Öğrenciler paketi içe aktarınca kelimeler '
                  'kendi kelime defterlerine ve tekrar planlarına girer. Hesap ya da sunucu gerekmez.', style: context.text.bodySmall),
              const SizedBox(height: 12),
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Paket adı', hintText: 'örn. 5. hafta: Doktorda'), onChanged: (_) => setState(() {})),
              const SizedBox(height: 8),
              TextField(controller: _note, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Öğrencilere not (isteğe bağlı)')),
              SectionTitle('Sözlükten kelime ekle (${_ids.length})'),
              TextField(controller: _search, decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Almanca ya da Türkçe ara'), onChanged: (_) => setState(() {})),
              for (final l in matches)
                ListTile(
                  dense: true,
                  title: Text(l.headword),
                  subtitle: Text('${l.tr} · ${l.cefr}'),
                  trailing: const Icon(Icons.add_rounded),
                  onTap: () => setState(() {
                    _ids.add(l.id);
                    _search.clear();
                  }),
                ),
              const SizedBox(height: 8),
              Text('Ya da bir ünitenin kelimelerini ekle:', style: context.text.labelMedium),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                isExpanded: true,
                hint: const Text('Ünite seç'),
                items: [for (final (lv, u) in units) DropdownMenuItem(value: u.id, child: Text('$lv · ${u.number}: ${u.titleDe}', overflow: TextOverflow.ellipsis))],
                onChanged: (id) {
                  final unit = ref.read(contentProvider).unit(id!);
                  if (unit == null) return;
                  setState(() {
                    for (final v in {for (final l in unit.lessons) ...l.vocab}) {
                      if (!_ids.contains(v)) _ids.add(v);
                    }
                  });
                },
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final id in _ids)
                  if (lexicon.byId(id) case final l?)
                    InputChip(label: Text(l.headword), onDeleted: () => setState(() => _ids.remove(id))),
              ]),
              if (_ids.isEmpty) TextButton(onPressed: () => _addTopic('A1'), child: const Text('Örnek: 30 A1 kelimesiyle başla')),
              SectionTitle('Kendi kelimelerin (${_custom.length})'),
              Text('Sözlükte olmayan kelimeleri ekle. İsimleri artikeliyle yaz (der/die/das …).', style: context.text.bodySmall),
              const SizedBox(height: 6),
              TextField(controller: _customDe, decoration: const InputDecoration(labelText: 'Almanca', hintText: 'die Überweisung')),
              const SizedBox(height: 6),
              TextField(controller: _customTr, decoration: const InputDecoration(labelText: 'Türkçe', hintText: 'havale')),
              const SizedBox(height: 6),
              TextField(controller: _customEx, decoration: const InputDecoration(labelText: 'Örnek cümle (isteğe bağlı)')),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    if (_customDe.text.trim().isEmpty || _customTr.text.trim().isEmpty) return;
                    setState(() {
                      _custom.add(CustomWord(headword: _customDe.text.trim(), meaningTr: _customTr.text.trim(), example: _customEx.text.trim()));
                      _customDe.clear();
                      _customTr.clear();
                      _customEx.clear();
                    });
                  },
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Ekle'),
                ),
              ),
              for (final c in _custom)
                ListTile(
                  dense: true,
                  title: Text(c.headword),
                  subtitle: Text(c.meaningTr),
                  trailing: IconButton(tooltip: 'Kaldır', icon: const Icon(Icons.close_rounded), onPressed: () => setState(() => _custom.remove(c))),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: !ready
                    ? null
                    : () => context.push('/share', extra: WordPack(name: _name.text.trim(), note: _note.text.trim(), lexemeIds: List.of(_ids), custom: List.of(_custom), teacher: true)),
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Text('Paketi paylaş'),
              ),
              if (!ready) Text('Bir ad ve en az bir kelime gerekli.', style: context.text.bodySmall, textAlign: TextAlign.center),
            ]),
          ),
        ],
      ),
    );
  }
}
