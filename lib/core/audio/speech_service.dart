import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'voice_selection.dart';

/// Text-to-speech through the platform engine. Voice quality depends on
/// the device; this is not native-speaker audio and the UI says so.
abstract interface class SpeechService {
  /// Speaks German text. Returns false when no German voice/engine is
  /// available, so the UI can show a text-only state. With [wait] the
  /// future completes when speaking has finished (for playing a sequence);
  /// [pitch] lets dialogues sound like different speakers.
  Future<bool> speak(String text, {bool slow = false, bool wait = false, double pitch = 1.0});
  Future<void> stop();

  /// German voices on this device, best first (empty if unknown).
  Future<List<VoiceInfo>> germanVoices();

  /// The voice currently used, if one was selected explicitly.
  Future<VoiceInfo?> currentVoice();
}

class PlatformSpeechService implements SpeechService {
  PlatformSpeechService({this.normalRate = 0.45, this.preferredVoice});

  static const _googleEngine = 'com.google.android.tts';

  double normalRate;

  /// Voice name the learner picked in settings; null = automatic.
  final String? preferredVoice;

  FlutterTts? _tts;
  bool? _available;
  VoiceInfo? _voice;
  List<VoiceInfo> _voices = const [];

  Future<FlutterTts?> _engine() async {
    if (_available == false) return null;
    if (_tts != null) return _tts;
    try {
      final tts = FlutterTts();
      await _preferGoogleEngine(tts);
      final ok = await tts.isLanguageAvailable('de-DE');
      if (ok == false) {
        _available = false;
        return null;
      }
      await tts.setLanguage('de-DE');
      await tts.awaitSpeakCompletion(false);
      await _selectVoice(tts);
      _available = true;
      return _tts = tts;
    } catch (e) {
      debugPrint('TTS unavailable: $e');
      _available = false;
      return null;
    }
  }

  /// Google's engine has the best German voices on most Android phones,
  /// but some manufacturers make their own engine the default.
  Future<void> _preferGoogleEngine(FlutterTts tts) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final engines = (await tts.getEngines as List?)?.map((e) => e.toString()).toList() ?? const [];
      final current = await tts.getDefaultEngine;
      if (engines.contains(_googleEngine) && current != _googleEngine) {
        await tts.setEngine(_googleEngine);
      }
    } catch (e) {
      debugPrint('TTS engine selection skipped: $e');
    }
  }

  /// Picks the best installed German voice instead of the engine default,
  /// which is often a low-quality or network-only voice.
  Future<void> _selectVoice(FlutterTts tts) async {
    try {
      final raw = await tts.getVoices;
      _voices = [for (final v in (raw as List?) ?? const []) ?VoiceInfo.fromPlatform(v)];
      final pick = pickVoice(_voices, preferredName: preferredVoice);
      if (pick != null) {
        await tts.setVoice(pick.toPlatform());
        _voice = pick;
      }
    } catch (e) {
      // Keep the engine's default voice; speaking still works.
      debugPrint('TTS voice selection skipped: $e');
    }
  }

  @override
  Future<bool> speak(String text, {bool slow = false, bool wait = false, double pitch = 1.0}) async {
    final tts = await _engine();
    if (tts == null) return false;
    try {
      // Web speech rates are on a different scale than mobile engines.
      final rate = kIsWeb ? (slow ? 0.6 : 0.95) : (slow ? normalRate * 0.6 : normalRate);
      await tts.setSpeechRate(rate);
      await tts.setPitch(pitch);
      await tts.stop();
      await tts.awaitSpeakCompletion(wait);
      await tts.speak(text);
      return true;
    } catch (e) {
      debugPrint('TTS failed: $e');
      return false;
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _tts?.stop();
    } catch (_) {}
  }

  @override
  Future<List<VoiceInfo>> germanVoices() async {
    await _engine();
    return germanVoicesRanked(_voices);
  }

  @override
  Future<VoiceInfo?> currentVoice() async {
    await _engine();
    return _voice;
  }
}

/// Silent implementation for tests and devices without TTS.
class SilentSpeechService implements SpeechService {
  final spoken = <String>[];
  @override
  Future<bool> speak(String text, {bool slow = false, bool wait = false, double pitch = 1.0}) async {
    spoken.add(text);
    return false;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<List<VoiceInfo>> germanVoices() async => const [];

  @override
  Future<VoiceInfo?> currentVoice() async => null;
}
