import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../net/api_result.dart';
import '../net/endpoints.dart';
import '../utils/app_log.dart';

class ApiException implements Exception {
  final int? statusCode;
  final String message;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ApiClient {
  final http.Client _client;
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = AppConfig.apiBaseUrl;
    final normalized = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$normalized').replace(queryParameters: query);
  }

  Map<String, String> _headers({Map<String, String>? extra}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (AppConfig.apiKey.isNotEmpty) 'X-API-Key': AppConfig.apiKey,
      if (AppConfig.userId.isNotEmpty) 'X-User-Id': AppConfig.userId,
    };
    if (extra != null) headers.addAll(extra);
    return headers;
  }

  /// GET with retry logic - returns ApiResult
  Future<ApiResult<Map<String, dynamic>>> getJsonResult(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    return _withRetry(() async {
      final uri = _uri(path, query);
      AppLog.network('GET', uri.toString());
      final res = await _client.get(uri, headers: _headers(extra: headers));
      AppLog.network('GET', uri.toString(), statusCode: res.statusCode);
      return _decodeJsonResult(res);
    });
  }

  /// POST with retry logic - returns ApiResult
  Future<ApiResult<Map<String, dynamic>>> postJsonResult(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    return _withRetry(() async {
      final uri = _uri(path);
      AppLog.network('POST', uri.toString());
      final res = await _client.post(
        uri,
        headers: _headers(extra: headers),
        body: body == null ? null : jsonEncode(body),
      );
      AppLog.network('POST', uri.toString(), statusCode: res.statusCode);
      return _decodeJsonResult(res);
    });
  }

  /// Legacy methods - kept for backwards compatibility
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final res = await _client.get(
      _uri(path, query),
      headers: _headers(extra: headers),
    );
    return _decodeJson(res);
  }

  Future<Map<String, dynamic>> postJson(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final res = await _client.post(
      _uri(path),
      headers: _headers(extra: headers),
      body: body == null ? null : jsonEncode(body),
    );
    return _decodeJson(res);
  }

  /// Retry wrapper with exponential backoff
  Future<ApiResult<T>> _withRetry<T>(
    Future<ApiResult<T>> Function() request,
  ) async {
    int attempt = 0;
    Duration backoff = NetConfig.initialBackoff;

    while (true) {
      attempt++;

      try {
        final result = await request();

        // Check if retryable based on status code
        if (result.isFailure) {
          final failure = result as ApiFailure<T>;

          // Don't retry client errors (4xx except timeout)
          if (!failure.isRetryable) {
            return result;
          }

          // Check if we should retry server errors
          if (attempt < NetConfig.maxRetries) {
            AppLog.w(
              'Request failed (attempt $attempt/${NetConfig.maxRetries}), retrying in ${backoff.inMilliseconds}ms...',
            );
            await Future.delayed(backoff);
            backoff = Duration(
              milliseconds:
                  (backoff.inMilliseconds * NetConfig.backoffMultiplier)
                      .toInt()
                      .clamp(
                        NetConfig.initialBackoff.inMilliseconds,
                        NetConfig.maxBackoff.inMilliseconds,
                      ),
            );
            continue;
          }
        }

        return result;
      } catch (e, st) {
        final failure = ApiResultFactory.fromException<T>(e, st);

        // Retry on network/timeout errors
        if (failure.isRetryable && attempt < NetConfig.maxRetries) {
          AppLog.w(
            'Network error (attempt $attempt/${NetConfig.maxRetries}), retrying in ${backoff.inMilliseconds}ms...',
          );
          await Future.delayed(backoff);
          backoff = Duration(
            milliseconds: (backoff.inMilliseconds * NetConfig.backoffMultiplier)
                .toInt()
                .clamp(
                  NetConfig.initialBackoff.inMilliseconds,
                  NetConfig.maxBackoff.inMilliseconds,
                ),
          );
          continue;
        }

        AppLog.e(
          'Request failed after $attempt attempts',
          error: e,
          stackTrace: st,
        );
        return failure;
      }
    }
  }

  ApiResult<Map<String, dynamic>> _decodeJsonResult(http.Response res) {
    final text = res.body;

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final errorType = ApiResultFactory.errorTypeFromStatus(res.statusCode);
      return ApiFailure(
        errorType,
        text.isEmpty ? 'HTTP ${res.statusCode}' : text,
        statusCode: res.statusCode,
      );
    }

    if (text.isEmpty) return const ApiSuccess(<String, dynamic>{});

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) return ApiSuccess(decoded);
      return ApiSuccess({'data': decoded});
    } catch (e) {
      return ApiFailure(
        ApiErrorType.unknown,
        'Failed to parse response: $e',
        cause: e,
      );
    }
  }

  Map<String, dynamic> _decodeJson(http.Response res) {
    final text = res.body;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ApiException(
        text.isEmpty ? 'HTTP ${res.statusCode}' : text,
        statusCode: res.statusCode,
      );
    }
    if (text.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(text);
    if (decoded is Map<String, dynamic>) return decoded;
    return {'data': decoded};
  }

  Future<Map<String, dynamic>> putJson(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final res = await _client.put(
      _uri(path),
      headers: _headers(extra: headers),
      body: body == null ? null : jsonEncode(body),
    );
    return _decodeJson(res);
  }

  Future<Map<String, dynamic>> deleteJson(
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final uri = _uri(path);
    final request = http.Request('DELETE', uri)
      ..headers.addAll(_headers(extra: headers));
    if (body != null) {
      request.body = jsonEncode(body);
    }
    final streamed = await _client.send(request);
    final res = await http.Response.fromStream(streamed);
    return _decodeJson(res);
  }
}
