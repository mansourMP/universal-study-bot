import 'package:flutter/foundation.dart';

/// Minimal logger wrapper.
/// Debug: console output
/// Release: only errors (no spam)
class AppLog {
  static const String _tag = 'DragonChinese';

  /// Debug level - only in debug builds
  static void d(String message, {String? tag}) {
    if (kDebugMode) {
      debugPrint('[${tag ?? _tag}] $message');
    }
  }

  /// Info level - always logged
  static void i(String message, {String? tag}) {
    debugPrint('[${tag ?? _tag}] ℹ️ $message');
  }

  /// Warning level - always logged
  static void w(String message, {String? tag}) {
    debugPrint('[${tag ?? _tag}] ⚠️ $message');
  }

  /// Error level - always logged with optional error and stack trace
  static void e(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('[${tag ?? _tag}] ❌ $message');
    if (error != null) {
      buffer.writeln('  Error: $error');
    }
    if (stackTrace != null && kDebugMode) {
      buffer.writeln(
        '  Stack: ${stackTrace.toString().split('\n').take(5).join('\n  ')}',
      );
    }
    debugPrint(buffer.toString());

    // TODO: Add Crashlytics/Sentry reporting here in production
    // if (!kDebugMode) {
    //   FirebaseCrashlytics.instance.recordError(error, stackTrace);
    // }
  }

  /// Network request log - only in debug
  static void network(
    String method,
    String url, {
    int? statusCode,
    String? error,
  }) {
    if (!kDebugMode) return;

    if (error != null) {
      debugPrint('[Network] ❌ $method $url - $error');
    } else if (statusCode != null) {
      final emoji = statusCode < 400 ? '✓' : '✗';
      debugPrint('[Network] $emoji $method $url [$statusCode]');
    } else {
      debugPrint('[Network] → $method $url');
    }
  }
}
