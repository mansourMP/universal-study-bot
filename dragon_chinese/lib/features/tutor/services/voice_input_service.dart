import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class VoiceCaptureResult {
  final String transcript;
  final double confidence;
  final int durationMs;

  const VoiceCaptureResult({
    required this.transcript,
    required this.confidence,
    required this.durationMs,
  });
}

class VoiceInputService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final Stopwatch _stopwatch = Stopwatch();

  bool _initialized = false;
  bool _isListening = false;
  bool _isStarting = false;
  String _transcript = '';
  double _confidence = 0.0;
  String? _localeId;
  String _lastPreferredLanguage = 'auto';

  bool get isListening => _isListening;

  Future<bool> startListening({
    String preferredLanguage = 'zh',
    ValueChanged<String>? onPartialTranscript,
    ValueChanged<String>? onStatusChanged,
    ValueChanged<String>? onError,
  }) async {
    if (_isListening || _isStarting) return false;
    _isStarting = true;
    final ok = await _ensureInitialized(
      preferredLanguage: preferredLanguage,
      onStatusChanged: onStatusChanged,
      onError: onError,
    );
    if (!ok) {
      _isStarting = false;
      return false;
    }

    if (_lastPreferredLanguage != preferredLanguage) {
      _localeId = await _resolveLocale(preferredLanguage);
      _lastPreferredLanguage = preferredLanguage;
    }

    try {
      await _speech.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      _transcript = '';
      _confidence = 0.0;
      _stopwatch
        ..reset()
        ..start();
      await _speech.listen(
        localeId: _localeId,
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        listenOptions: stt.SpeechListenOptions(
          cancelOnError: true,
          partialResults: true,
        ),
        onResult: (SpeechRecognitionResult result) {
          _transcript = result.recognizedWords.trim();
          _confidence = result.hasConfidenceRating ? result.confidence : 0.0;
          onPartialTranscript?.call(_transcript);
          if (result.finalResult) {
            onStatusChanged?.call('done');
          }
        },
      );
      _isListening = true;
      return true;
    } catch (e) {
      _isListening = false;
      _stopwatch.stop();
      onError?.call('Could not start microphone capture');
      if (kDebugMode) {
        debugPrint('VoiceInputService.startListening error: $e');
      }
      return false;
    } finally {
      _isStarting = false;
    }
  }

  Future<VoiceCaptureResult?> stopListening() async {
    try {
      await _speech.stop();
    } catch (_) {
      // no-op
    }
    await Future<void>.delayed(const Duration(milliseconds: 140));

    _stopwatch.stop();
    _isListening = false;
    final transcript = _transcript.trim();
    if (transcript.isEmpty && _stopwatch.elapsedMilliseconds <= 0) {
      return null;
    }
    return VoiceCaptureResult(
      transcript: _transcript.trim(),
      confidence: _confidence,
      durationMs: max(400, _stopwatch.elapsedMilliseconds),
    );
  }

  Future<void> cancel() async {
    _isStarting = false;
    _isListening = false;
    _stopwatch.stop();
    try {
      await _speech.cancel();
    } catch (_) {
      // no-op
    }
  }

  String statusLabel(String rawStatus) {
    switch (rawStatus.toLowerCase()) {
      case 'listening':
        return 'Listening...';
      case 'notlistening':
        return 'Processing...';
      case 'done':
        return 'Processing...';
      default:
        return 'Listening...';
    }
  }

  Future<bool> _ensureInitialized({
    required String preferredLanguage,
    ValueChanged<String>? onStatusChanged,
    ValueChanged<String>? onError,
  }) async {
    if (_initialized) return true;
    try {
      final ok = await _speech.initialize(
        onStatus: (status) {
          if (!_isStarting &&
              (status.toLowerCase() == 'notlistening' ||
                  status.toLowerCase() == 'done')) {
            _isListening = false;
          }
          onStatusChanged?.call(status);
        },
        onError: (SpeechRecognitionError err) {
          _isStarting = false;
          _isListening = false;
          onError?.call(err.errorMsg);
        },
      );
      _initialized = ok;
      if (!ok) return false;
      _localeId = await _resolveLocale(preferredLanguage);
      return true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('VoiceInputService.initialize error: $e');
      }
      _initialized = false;
      return false;
    }
  }

  Future<String?> _resolveLocale(String preferredLanguage) async {
    try {
      final locales = await _speech.locales();
      if (locales.isEmpty) return null;

      final lang = preferredLanguage.trim().toLowerCase();
      if (lang.isEmpty) return null;
      if (lang == 'auto') return null;

      final preferredLocaleByLang = <String, String>{
        'zh': 'zh_cn',
        'en': 'en_us',
        'ja': 'ja_jp',
        'ko': 'ko_kr',
        'es': 'es_es',
        'fr': 'fr_fr',
        'de': 'de_de',
        'ru': 'ru_ru',
      };

      final preferredLocale = preferredLocaleByLang[lang];
      final exact = preferredLocale == null
          ? const <stt.LocaleName>[]
          : locales.where((l) => l.localeId.toLowerCase() == preferredLocale);
      if (exact.isNotEmpty) return exact.first.localeId;

      final startsWithLang = locales.where(
        (l) => l.localeId.toLowerCase().startsWith(lang),
      );
      if (startsWithLang.isNotEmpty) {
        return startsWithLang.first.localeId;
      }

      return null;
    } catch (_) {
      return null;
    }
  }
}
