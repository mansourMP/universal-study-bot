import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/core/net/api_result.dart';
import 'package:dragon_chinese/core/widgets/network_state_gate.dart';

void main() {
  group('NetworkStateGate', () {
    testWidgets('shows skeleton loader when loading', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkStateGate<String>(
              result: null,
              isLoading: true,
              onRetry: () {},
              builder: (data) => Text(data),
            ),
          ),
        ),
      );

      // Should show skeleton loader (gradient container)
      expect(find.byType(Container), findsWidgets);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('shows error card with retry button on failure', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkStateGate<String>(
              result: const ApiFailure(ApiErrorType.network, 'Network error'),
              isLoading: false,
              onRetry: () {},
              builder: (data) => Text(data),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Should show error message and retry button
      expect(
        find.text('Network error. Check your internet connection.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsOneWidget);
    });

    testWidgets('calls onRetry when retry button pressed', (tester) async {
      var retryCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkStateGate<String>(
              result: const ApiFailure(ApiErrorType.network, 'Network error'),
              isLoading: false,
              onRetry: () => retryCalled = true,
              builder: (data) => Text(data),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retry'));
      expect(retryCalled, isTrue);
    });

    testWidgets('shows content on success', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkStateGate<String>(
              result: const ApiSuccess('Hello World'),
              isLoading: false,
              onRetry: () {},
              builder: (data) => Text(data),
            ),
          ),
        ),
      );

      expect(find.text('Hello World'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('shows empty state for empty list', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NetworkStateGate<List<String>>(
              result: const ApiSuccess([]),
              isLoading: false,
              onRetry: () {},
              emptyMessage: 'No items found',
              builder: (data) => Text('Items: ${data.length}'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No items found'), findsOneWidget);
      expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
    });
  });

  group('ApiResult', () {
    test('ApiSuccess returns data', () {
      const result = ApiSuccess<int>(42);
      expect(result.isSuccess, isTrue);
      expect(result.isFailure, isFalse);
      expect(result.dataOrNull, equals(42));
      expect(result.dataOrThrow, equals(42));
    });

    test('ApiFailure returns error info', () {
      const result = ApiFailure<int>(
        ApiErrorType.network,
        'Connection failed',
        statusCode: 503,
      );
      expect(result.isSuccess, isFalse);
      expect(result.isFailure, isTrue);
      expect(result.dataOrNull, isNull);
      expect(result.userMessage, contains('Network error'));
      expect(result.isRetryable, isTrue);
    });

    test('Non-retryable errors are identified', () {
      const unauthorized = ApiFailure<int>(
        ApiErrorType.unauthorized,
        'Unauthorized',
      );
      const forbidden = ApiFailure<int>(ApiErrorType.forbidden, 'Forbidden');
      const notFound = ApiFailure<int>(ApiErrorType.notFound, 'Not found');

      expect(unauthorized.isRetryable, isFalse);
      expect(forbidden.isRetryable, isFalse);
      expect(notFound.isRetryable, isFalse);
    });

    test('Retryable errors are identified', () {
      const timeout = ApiFailure<int>(ApiErrorType.timeout, 'Timeout');
      const network = ApiFailure<int>(ApiErrorType.network, 'Network');
      const server = ApiFailure<int>(ApiErrorType.serverError, 'Server error');

      expect(timeout.isRetryable, isTrue);
      expect(network.isRetryable, isTrue);
      expect(server.isRetryable, isTrue);
    });

    test('fold works correctly', () {
      const success = ApiSuccess<int>(10);
      const failure = ApiFailure<int>(ApiErrorType.unknown, 'Error');

      final successResult = success.fold(
        onSuccess: (data) => 'Value: $data',
        onFailure: (f) => 'Error: ${f.message}',
      );
      expect(successResult, equals('Value: 10'));

      final failureResult = failure.fold(
        onSuccess: (data) => 'Value: $data',
        onFailure: (f) => 'Error: ${f.message}',
      );
      expect(failureResult, equals('Error: Error'));
    });
  });
}
