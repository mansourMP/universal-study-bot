import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:dragon_chinese/core/network/api_client.dart';
import 'package:dragon_chinese/core/net/api_result.dart';
import 'package:dragon_chinese/core/net/endpoints.dart';

void main() {
  group('ApiClient retry and error handling', () {
    test('returns ApiFailure on 500 server error', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Internal Server Error', 500);
      });

      final apiClient = ApiClient(client: mockClient);
      final result = await apiClient.getJsonResult(Endpoints.pathJourney);

      expect(result.isFailure, isTrue);
      final failure = result as ApiFailure;
      expect(failure.errorType, equals(ApiErrorType.serverError));
      expect(failure.statusCode, equals(500));
      expect(failure.isRetryable, isTrue);
    });

    test('returns ApiSuccess on 200 response', () async {
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'nodes': [], 'total': 0}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final result = await apiClient.getJsonResult(Endpoints.pathJourney);

      expect(result.isSuccess, isTrue);
      final success = result as ApiSuccess;
      expect(success.data, isA<Map<String, dynamic>>());
    });

    test('returns unauthorized failure on 401', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Unauthorized', 401);
      });

      final apiClient = ApiClient(client: mockClient);
      final result = await apiClient.getJsonResult(Endpoints.pathJourney);

      expect(result.isFailure, isTrue);
      final failure = result as ApiFailure;
      expect(failure.errorType, equals(ApiErrorType.unauthorized));
      expect(failure.isRetryable, isFalse);
    });

    test('returns not found failure on 404', () async {
      final mockClient = MockClient((request) async {
        return http.Response('Not Found', 404);
      });

      final apiClient = ApiClient(client: mockClient);
      final result = await apiClient.getJsonResult(Endpoints.pathJourney);

      expect(result.isFailure, isTrue);
      final failure = result as ApiFailure;
      expect(failure.errorType, equals(ApiErrorType.notFound));
      expect(failure.isRetryable, isFalse);
    });

    test('retries on 503 then succeeds', () async {
      var attempts = 0;
      final mockClient = MockClient((request) async {
        attempts++;
        if (attempts < 2) {
          return http.Response('Service Unavailable', 503);
        }
        return http.Response(
          jsonEncode({'data': 'success'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final apiClient = ApiClient(client: mockClient);
      final result = await apiClient.getJsonResult(Endpoints.pathJourney);

      // Should have retried
      expect(attempts, greaterThan(1));
      expect(result.isSuccess, isTrue);
    });

    test('does not retry on 400 bad request', () async {
      var attempts = 0;
      final mockClient = MockClient((request) async {
        attempts++;
        return http.Response('Bad Request', 400);
      });

      final apiClient = ApiClient(client: mockClient);
      final result = await apiClient.getJsonResult(Endpoints.pathJourney);

      // Should NOT have retried
      expect(attempts, equals(1));
      expect(result.isFailure, isTrue);
      final failure = result as ApiFailure;
      expect(failure.errorType, equals(ApiErrorType.badRequest));
    });
  });
}
