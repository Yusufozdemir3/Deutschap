/// A text-to-speech voice as reported by the platform engine.
class VoiceInfo {
  const VoiceInfo({required this.name, required this.locale, this.quality = '', this.networkRequired = false, this.installed = true});

  final String name;
  final String locale;

  /// Android: "very high" … "very low"; iOS: "premium" / "enhanced" /
  /// "default"; web: empty.
  final String quality;
  final bool networkRequired;
  final bool installed;

  bool get isGerman => locale.toLowerCase().replaceAll('_', '-').startsWith('de');

  Map<String, String> toPlatform() => {'name': name, 'locale': locale};

  /// Parses a map from flutter_tts `getVoices`, tolerating the different
  /// keys each platform uses. Returns null for unusable entries.
  static VoiceInfo? fromPlatform(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name']?.toString();
    final locale = raw['locale']?.toString();
    if (name == null || locale == null) return null;
    final features = raw['features']?.toString() ?? '';
    return VoiceInfo(
      name: name,
      locale: locale,
      quality: raw['quality']?.toString().toLowerCase() ?? '',
      networkRequired: raw['network_required']?.toString() == '1',
      installed: !features.contains('notInstalled'),
    );
  }

  /// Short label for settings: quality and whether it works offline.
  String get descriptionTr {
    final q = switch (quality) {
      'very high' || 'premium' => 'en yüksek kalite',
      'high' || 'enhanced' => 'yüksek kalite',
      'normal' || 'default' => 'normal kalite',
      'low' || 'very low' => 'düşük kalite',
      _ => '',
    };
    final region = switch (locale.toLowerCase().replaceAll('_', '-')) {
      final l when l.startsWith('de-at') => 'Avusturya',
      final l when l.startsWith('de-ch') => 'İsviçre',
      _ => 'Almanya',
    };
    return [region, if (q.isNotEmpty) q, networkRequired ? 'internet gerekir' : 'çevrimdışı çalışır'].join(' · ');
  }
}

/// Higher is better. Reliability first (installed, works offline), then
/// quality, then standard German from Germany as the default variety.
int voiceScore(VoiceInfo v) {
  if (!v.isGerman || !v.installed) return -1;
  var s = 0;
  if (!v.networkRequired) s += 100; // never silent without internet
  s += switch (v.quality) {
    'very high' || 'premium' => 40,
    'high' || 'enhanced' => 30,
    'normal' || 'default' => 10,
    _ => 0,
  };
  final locale = v.locale.toLowerCase().replaceAll('_', '-');
  if (locale == 'de-de') s += 8;
  // Web: browser voices report no quality; the neural/online ones are
  // clearly better than the old system voices.
  final name = v.name.toLowerCase();
  if (name.contains('natural') || name.contains('neural') || name.contains('google')) s += 20;
  if (name.contains('premium') || name.contains('enhanced')) s += 5;
  return s;
}

/// The best German voice, or the learner's own choice when it is still
/// available. Null when the device has no usable German voice.
VoiceInfo? pickVoice(List<VoiceInfo> voices, {String? preferredName}) {
  final german = voices.where((v) => voiceScore(v) >= 0).toList();
  if (german.isEmpty) return null;
  if (preferredName != null) {
    for (final v in german) {
      if (v.name == preferredName) return v;
    }
  }
  german.sort((a, b) {
    final d = voiceScore(b).compareTo(voiceScore(a));
    return d != 0 ? d : a.name.compareTo(b.name);
  });
  return german.first;
}

/// German voices for the settings list, best first.
List<VoiceInfo> germanVoicesRanked(List<VoiceInfo> voices) => voices.where((v) => voiceScore(v) >= 0).toList()
  ..sort((a, b) {
    final d = voiceScore(b).compareTo(voiceScore(a));
    return d != 0 ? d : a.name.compareTo(b.name);
  });
