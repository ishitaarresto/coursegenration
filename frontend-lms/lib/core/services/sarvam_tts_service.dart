import 'dart:html' as html;
import 'package:dio/dio.dart';
import 'api_client.dart';
import '../config/api_config.dart';

/// Sarvam TTS player for Flutter Web.
///
/// Flow:
///   1. POST /api/v1/tts/speak  → backend calls Sarvam, stores MP3, returns URL
///   2. Set AudioElement.src = that URL and call play()
///   3. Browser streams the MP3 natively — no binary data in Dart
///
/// Usage:
///   _tts.onStateChange = () { if (mounted) setState(() {}); };
///   _tts.speak(text);
class SarvamTtsPlayer {
  html.AudioElement? _audio;
  int _gen = 0; // incremented on each speak/stop to cancel stale async work

  bool _loading = false;
  bool _speaking = false;
  bool _paused = false;

  void Function()? onStateChange;

  bool get isLoading => _loading;
  bool get isSpeaking => _speaking && !_paused;
  bool get isPaused => _speaking && _paused;
  bool get isActive => _loading || _speaking;

  void _notify() => onStateChange?.call();

  Future<void> speak(String text) async {
    stop(); // cancel any current audio; increments _gen
    final gen = ++_gen;
    _loading = true;
    _notify();

    try {
      final resp = await apiClient.post(
        '/api/v1/tts/speak',
        data: {'text': text},
        options: Options(receiveTimeout: const Duration(seconds: 60)),
      );
      if (_gen != gen) return; // superseded by stop() or a newer speak()

      final relUrl = resp.data['url'] as String;
      final fullUrl = '${ApiConfig.baseUrl}$relUrl';

      final audio = html.AudioElement()..src = fullUrl;
      _audio = audio;

      audio.onEnded.listen((_) {
        if (_gen == gen) {
          _speaking = false;
          _paused = false;
          _notify();
        }
      });
      audio.onError.listen((_) {
        if (_gen == gen) {
          _loading = false;
          _speaking = false;
          _notify();
        }
      });

      // play() must be called synchronously here (no await gap).
      // The browser starts streaming the MP3 URL natively.
      audio.play();
      _loading = false;
      _speaking = true;
      _paused = false;
      _notify();
    } on DioException catch (e) {
      if (_gen != gen) return;
      _loading = false;
      _speaking = false;
      _notify();
      final status = e.response?.statusCode;
      final detail = e.response?.data?['detail'] ?? e.message;
      throw Exception('TTS failed (HTTP $status): $detail');
    } catch (_) {
      if (_gen != gen) return;
      _loading = false;
      _speaking = false;
      _notify();
    }
  }

  void pause() {
    if (_speaking && !_paused) {
      _audio?.pause();
      _paused = true;
      _notify();
    }
  }

  void resume() {
    if (_speaking && _paused) {
      _audio?.play();
      _paused = false;
      _notify();
    }
  }

  void stop() {
    _gen++;
    _audio?.pause();
    _audio = null;
    _loading = false;
    _speaking = false;
    _paused = false;
    _notify();
  }

  void dispose() {
    _audio?.pause();
    _audio = null;
    onStateChange = null;
  }
}
