import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// Text-to-speech through the platform engine. Voice quality depends on
/// the device; this is not native-speaker audio and the UI says so.
abstract interface class SpeechService {
  /// Speaks German text. Returns false when no German voice/engine is
  /// available, so the UI can show a text-only state.
  Future<bool> speak(String text, {bool slow = false});
  Future<void> stop();
}

class PlatformSpeechService implements SpeechService {
  PlatformSpeechService({this.normalRate = 0.45});

  double normalRate;
  FlutterTts? _tts;
  bool? _available;

  Future<FlutterTts?> _engine() async {
    if (_available == false) return null;
    if (_tts != null) return _tts;
    try {
      final tts = FlutterTts();
      final ok = await tts.isLanguageAvailable('de-DE');
      if (ok == false) {
        _available = false;
        return null;
      }
      await tts.setLanguage('de-DE');
      await tts.awaitSpeakCompletion(false);
      _available = true;
      return _tts = tts;
    } catch (e) {
      debugPrint('TTS unavailable: $e');
      _available = false;
      return null;
    }
  }

  @override
  Future<bool> speak(String text, {bool slow = false}) async {
    final tts = await _engine();
    if (tts == null) return false;
    try {
      // Web speech rates are on a different scale than mobile engines.
      final rate = kIsWeb ? (slow ? 0.6 : 0.95) : (slow ? normalRate * 0.6 : normalRate);
      await tts.setSpeechRate(rate);
      await tts.stop();
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
}

/// Silent implementation for tests and devices without TTS.
class SilentSpeechService implements SpeechService {
  final spoken = <String>[];
  @override
  Future<bool> speak(String text, {bool slow = false}) async {
    spoken.add(text);
    return false;
  }

  @override
  Future<void> stop() async {}
}
