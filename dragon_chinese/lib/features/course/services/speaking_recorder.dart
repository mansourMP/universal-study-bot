import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:shared_preferences/shared_preferences.dart';

enum SpeakingPermission { granted, denied }

class SpeakingRecording {
  final String path;
  final int durationMs;
  final String transcript;
  final double confidence;

  SpeakingRecording({
    required this.path,
    required this.durationMs,
    this.transcript = '',
    this.confidence = 0.0,
  });
}

abstract class SpeakingRecorder {
  bool get isRecording;
  Future<SpeakingPermission> checkPermission();
  Future<SpeakingPermission> requestPermission();
  Future<void> start();
  Future<SpeakingRecording> stop();
}

class SpeakingRecorderService {
  static SpeakingRecorder _instance = HybridSpeakingRecorder();

  static SpeakingRecorder get instance => _instance;

  static void setInstanceForTest(SpeakingRecorder recorder) {
    _instance = recorder;
  }
}

class HybridSpeakingRecorder implements SpeakingRecorder {
  final OnDeviceSpeakingRecorder _onDevice = OnDeviceSpeakingRecorder();
  final LocalSpeakingRecorder _local = LocalSpeakingRecorder();
  static const bool _allowLocalFallback = false;
  SpeakingRecorder? _active;

  @override
  bool get isRecording => (_active ?? _onDevice).isRecording;

  @override
  Future<SpeakingPermission> checkPermission() async {
    final onDevicePermission = await _onDevice.checkPermission();
    if (onDevicePermission == SpeakingPermission.granted) {
      _active = _onDevice;
      return onDevicePermission;
    }
    if (_allowLocalFallback) {
      return _local.checkPermission();
    }
    return SpeakingPermission.denied;
  }

  @override
  Future<SpeakingPermission> requestPermission() async {
    final onDevicePermission = await _onDevice.requestPermission();
    if (onDevicePermission == SpeakingPermission.granted) {
      _active = _onDevice;
      return onDevicePermission;
    }
    if (_allowLocalFallback) {
      return _local.requestPermission();
    }
    return SpeakingPermission.denied;
  }

  @override
  Future<void> start() async {
    final onDevicePermission = await _onDevice.requestPermission();
    if (onDevicePermission == SpeakingPermission.granted) {
      _active = _onDevice;
      await _onDevice.start();
      return;
    }
    if (!_allowLocalFallback) {
      throw StateError('Speech recognition unavailable on this build');
    }
    _active = _local;
    await _local.start();
  }

  @override
  Future<SpeakingRecording> stop() async {
    final active = _active;
    if (active == null) {
      return SpeakingRecording(path: '', durationMs: 0);
    }
    final recording = await active.stop();
    _active = null;
    return recording;
  }
}

class OnDeviceSpeakingRecorder implements SpeakingRecorder {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final Stopwatch _stopwatch = Stopwatch();
  bool _recording = false;
  bool _initialized = false;
  String? _preferredLocale;
  String _transcript = '';
  double _confidence = 0.0;

  @override
  bool get isRecording => _recording;

  Future<bool> _ensureInitialized() async {
    if (_initialized) return true;
    try {
      final ok = await _speech.initialize();
      _initialized = ok;
      if (_initialized) {
        _preferredLocale = await _resolveLocale();
      }
      return ok;
    } on MissingPluginException {
      _initialized = false;
      return false;
    } catch (_) {
      _initialized = false;
      return false;
    }
  }

  @override
  Future<SpeakingPermission> checkPermission() async {
    final ok = await _ensureInitialized();
    return ok ? SpeakingPermission.granted : SpeakingPermission.denied;
  }

  @override
  Future<SpeakingPermission> requestPermission() async {
    final ok = await _ensureInitialized();
    return ok ? SpeakingPermission.granted : SpeakingPermission.denied;
  }

  @override
  Future<void> start() async {
    final permission = await requestPermission();
    if (permission != SpeakingPermission.granted) {
      throw StateError('Microphone permission denied');
    }
    _transcript = '';
    _confidence = 0.0;
    _stopwatch
      ..reset()
      ..start();
    _recording = true;
    try {
      await _speech.listen(
        localeId: _preferredLocale,
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 2),
        cancelOnError: false,
        partialResults: true,
        onResult: (result) {
          _transcript = result.recognizedWords.trim();
          _confidence = result.hasConfidenceRating ? result.confidence : 0.0;
        },
      );
    } catch (_) {
      await _speech.listen(
        localeId: _preferredLocale,
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 2),
        cancelOnError: false,
        partialResults: true,
        onResult: (result) {
          _transcript = result.recognizedWords.trim();
          _confidence = result.hasConfidenceRating ? result.confidence : 0.0;
        },
      );
    }
  }

  @override
  Future<SpeakingRecording> stop() async {
    if (!_recording) {
      return SpeakingRecording(path: '', durationMs: 0);
    }
    await _speech.stop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _stopwatch.stop();
    _recording = false;
    final durationMs = max(500, _stopwatch.elapsedMilliseconds);
    return SpeakingRecording(
      path: '',
      durationMs: durationMs,
      transcript: _transcript,
      confidence: _confidence,
    );
  }

  Future<String?> _resolveLocale() async {
    try {
      final locales = await _speech.locales();
      if (locales.isEmpty) return null;
      final exact = locales.where((l) => l.localeId == 'zh_CN');
      if (exact.isNotEmpty) return exact.first.localeId;
      final zh = locales.where(
        (l) => l.localeId.toLowerCase().startsWith('zh'),
      );
      if (zh.isNotEmpty) return zh.first.localeId;
      return null;
    } catch (_) {
      return null;
    }
  }
}

class LocalSpeakingRecorder implements SpeakingRecorder {
  static const String _permKey = 'speaking_permission_granted_v1';
  final Stopwatch _stopwatch = Stopwatch();
  bool _recording = false;

  @override
  bool get isRecording => _recording;

  @override
  Future<SpeakingPermission> checkPermission() async {
    final prefs = await SharedPreferences.getInstance();
    final granted = prefs.getBool(_permKey) ?? true;
    return granted ? SpeakingPermission.granted : SpeakingPermission.denied;
  }

  @override
  Future<SpeakingPermission> requestPermission() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_permKey, true);
    return SpeakingPermission.granted;
  }

  @override
  Future<void> start() async {
    final permission = await checkPermission();
    if (permission != SpeakingPermission.granted) {
      throw StateError('Microphone permission denied');
    }
    _stopwatch
      ..reset()
      ..start();
    _recording = true;
  }

  @override
  Future<SpeakingRecording> stop() async {
    if (!_recording) {
      return SpeakingRecording(path: '', durationMs: 0);
    }
    _stopwatch.stop();
    _recording = false;
    final durationMs = max(500, _stopwatch.elapsedMilliseconds);
    final dir = Directory.systemTemp;
    final file = File(
      '${dir.path}/speaking_${DateTime.now().millisecondsSinceEpoch}.wav',
    );
    await file.writeAsBytes(_silentWavBytes(durationMs));
    return SpeakingRecording(path: file.path, durationMs: durationMs);
  }

  List<int> _silentWavBytes(int durationMs) {
    const sampleRate = 16000;
    const channels = 1;
    const bitsPerSample = 16;
    final numSamples = (durationMs * sampleRate ~/ 1000).clamp(
      1,
      10 * sampleRate,
    );
    final dataSize = numSamples * channels * (bitsPerSample ~/ 8);
    final totalSize = 44 + dataSize;
    final bytes = Uint8List(totalSize);
    final bd = ByteData.view(bytes.buffer);

    void writeString(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes[offset + i] = value.codeUnitAt(i);
      }
    }

    writeString(0, 'RIFF');
    bd.setUint32(4, 36 + dataSize, Endian.little);
    writeString(8, 'WAVE');
    writeString(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, channels, Endian.little);
    bd.setUint32(24, sampleRate, Endian.little);
    final byteRate = sampleRate * channels * (bitsPerSample ~/ 8);
    bd.setUint32(28, byteRate, Endian.little);
    final blockAlign = channels * (bitsPerSample ~/ 8);
    bd.setUint16(32, blockAlign, Endian.little);
    bd.setUint16(34, bitsPerSample, Endian.little);
    writeString(36, 'data');
    bd.setUint32(40, dataSize, Endian.little);
    return bytes;
  }
}

class FakeSpeakingRecorder implements SpeakingRecorder {
  SpeakingPermission permission;
  bool _recording = false;
  int durationMs;
  String path;

  FakeSpeakingRecorder({
    this.permission = SpeakingPermission.granted,
    this.durationMs = 1200,
    this.path = '/tmp/fake.wav',
  });

  @override
  bool get isRecording => _recording;

  @override
  Future<SpeakingPermission> checkPermission() async => permission;

  @override
  Future<SpeakingPermission> requestPermission() async => permission;

  @override
  Future<void> start() async {
    if (permission != SpeakingPermission.granted) {
      throw StateError('Microphone permission denied');
    }
    _recording = true;
  }

  @override
  Future<SpeakingRecording> stop() async {
    _recording = false;
    return SpeakingRecording(path: path, durationMs: durationMs);
  }
}
