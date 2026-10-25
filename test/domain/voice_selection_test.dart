import 'package:deutschap/core/audio/voice_selection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Shapes as returned by flutter_tts on Android (Google engine).
  Map<String, String> android(String name, String locale, String quality, {bool network = false, String features = ''}) => {
        'name': name,
        'locale': locale,
        'quality': quality,
        'latency': 'normal',
        'network_required': network ? '1' : '0',
        'features': features,
      };

  List<VoiceInfo> parse(List<Object?> raw) => [for (final v in raw) ?VoiceInfo.fromPlatform(v)];

  test('picks an installed, offline, high-quality German voice over the network and default ones', () {
    final voices = parse([
      android('en-us-x-sfg-local', 'en-US', 'very high'),
      android('de-de-x-deb-network', 'de-DE', 'very high', network: true),
      android('de-DE-language', 'de-DE', 'normal'),
      android('de-de-x-deg-local', 'de-DE', 'high'),
      android('de-de-x-nfh-local', 'de-DE', 'very high', features: 'notInstalled'),
    ]);
    expect(pickVoice(voices)!.name, 'de-de-x-deg-local');
  });

  test('falls back to a network voice when nothing works offline', () {
    final voices = parse([android('de-de-x-deb-network', 'de-DE', 'very high', network: true)]);
    expect(pickVoice(voices)!.name, 'de-de-x-deb-network');
  });

  test('the learner\'s choice wins while it is still installed', () {
    final voices = parse([android('de-de-x-deg-local', 'de-DE', 'high'), android('de-de-x-dea-local', 'de-DE', 'normal')]);
    expect(pickVoice(voices, preferredName: 'de-de-x-dea-local')!.name, 'de-de-x-dea-local');
    expect(pickVoice(voices, preferredName: 'removed-voice')!.name, 'de-de-x-deg-local');
  });

  test('prefers Germany when quality is equal; Austrian and Swiss voices stay selectable', () {
    final voices = parse([android('de-at-x-a', 'de-AT', 'high'), android('de-de-x-b', 'de-DE', 'high'), android('de-ch-x-c', 'de-CH', 'high')]);
    expect(pickVoice(voices)!.locale, 'de-DE');
    expect(germanVoicesRanked(voices).length, 3);
    expect(germanVoicesRanked(voices).last.descriptionTr, isNot(contains('Almanya')));
  });

  test('iOS and web shapes', () {
    final ios = parse([
      {'name': 'Anna', 'locale': 'de-DE', 'quality': 'default'},
      {'name': 'Anna (Premium)', 'locale': 'de-DE', 'quality': 'premium'},
    ]);
    expect(pickVoice(ios)!.name, 'Anna (Premium)');
    final web = parse([
      {'name': 'Microsoft Hedda - German (Germany)', 'locale': 'de-DE'},
      {'name': 'Microsoft Katja Online (Natural) - German (Germany)', 'locale': 'de-DE'},
    ]);
    expect(pickVoice(web)!.name, contains('Natural'));
  });

  test('no German voice means no pick, and junk entries are ignored', () {
    expect(pickVoice(parse([android('en-us-x-a', 'en-US', 'high'), 'not a map', {'name': 'x'}])), isNull);
  });
}
