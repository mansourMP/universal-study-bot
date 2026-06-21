/// Typed result wrapper for API calls.
/// Use instead of returning null or empty collections on failure.
sealed class ApiResult<T> {
  const ApiResult();

  /// Check if result is successful
  bool get isSuccess => this is ApiSuccess<T>;
  bool get isFailure => this is ApiFailure<T>;

  /// Get data or throw
  T get dataOrThrow {
    if (this is ApiSuccess<T>) {
      return (this as ApiSuccess<T>).data;
    }
    throw (this as ApiFailure<T>).toException();
  }

  /// Get data or null
  T? get dataOrNull {
    if (this is ApiSuccess<T>) {
      return (this as ApiSuccess<T>).data;
    }
    return null;
  }

  /// Transform success data
  ApiResult<R> map<R>(R Function(T data) transform) {
    if (this is ApiSuccess<T>) {
      return ApiSuccess(transform((this as ApiSuccess<T>).data));
    }
    final failure = this as ApiFailure<T>;
    return ApiFailure(
      failure.errorType,
      failure.message,
      statusCode: failure.statusCode,
      cause: failure.cause,
    );
  }

  /// Fold to a single value
  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(ApiFailure<T> failure) onFailure,
  }) {
    if (this is ApiSuccess<T>) {
      return onSuccess((this as ApiSuccess<T>).data);
    }
    return onFailure(this as ApiFailure<T>);
  }
}

class ApiSuccess<T> extends ApiResult<T> {
  final T data;
  const ApiSuccess(this.data);
}

class ApiFailure<T> extends ApiResult<T> {
  final ApiErrorType errorType;
  final String message;
  final int? statusCode;
  final Object? cause;

  const ApiFailure(this.errorType, this.message, {this.statusCode, this.cause});

  /// Whether this error is retryable (transient failures)
  bool get isRetryable {
    switch (errorType) {
      case ApiErrorType.timeout:
      case ApiErrorType.network:
      case ApiErrorType.serverError:
        return true;
      case ApiErrorType.unauthorized:
      case ApiErrorType.forbidden:
      case ApiErrorType.notFound:
      case ApiErrorType.badRequest:
      case ApiErrorType.unknown:
        return false;
    }
  }

  /// User-friendly message
  String get userMessage {
    switch (errorType) {
      case ApiErrorType.timeout:
        return 'Request timed out. Check your connection.';
      case ApiErrorType.network:
        return 'Network error. Check your internet connection.';
      case ApiErrorType.serverError:
        return 'Server is temporarily unavailable. Try again.';
      case ApiErrorType.unauthorized:
        return 'Please sign in again.';
      case ApiErrorType.forbidden:
        return 'Access denied.';
      case ApiErrorType.notFound:
        return 'Content not found.';
      case ApiErrorType.badRequest:
        return 'Invalid request.';
      case ApiErrorType.unknown:
        return 'Something went wrong. Please try again.';
    }
  }

  Exception toException() => ApiResultException(this);
}

enum ApiErrorType {
  timeout,
  network,
  serverError, // 500, 502, 503, 504
  unauthorized, // 401
  forbidden, // 403
  notFound, // 404
  badRequest, // 400, 422
  unknown,
}

class ApiResultException implements Exception {
  final ApiFailure failure;
  const ApiResultException(this.failure);

  @override
  String toString() => 'ApiResultException: ${failure.message}';
}

/// Factory for creating ApiFailure from exceptions/status codes
class ApiResultFactory {
  static ApiErrorType errorTypeFromStatus(int statusCode) {
    if (statusCode == 401) return ApiErrorType.unauthorized;
    if (statusCode == 403) return ApiErrorType.forbidden;
    if (statusCode == 404) return ApiErrorType.notFound;
    if (statusCode == 400 || statusCode == 422) return ApiErrorType.badRequest;
    if (statusCode >= 500 && statusCode < 600) return ApiErrorType.serverError;
    return ApiErrorType.unknown;
  }

  static ApiFailure<T> fromException<T>(
    Object error, [
    StackTrace? stackTrace,
  ]) {
    final errorStr = error.toString().toLowerCase();

    // Network/socket errors
    if (errorStr.contains('socket') ||
        errorStr.contains('connection') ||
        errorStr.contains('host lookup')) {
      return ApiFailure<T>(
        ApiErrorType.network,
        'Network connection failed',
        cause: error,
      );
    }

    // Timeout
    if (errorStr.contains('timeout') || errorStr.contains('timed out')) {
      return ApiFailure<T>(
        ApiErrorType.timeout,
        'Request timed out',
        cause: error,
      );
    }

    return ApiFailure<T>(ApiErrorType.unknown, error.toString(), cause: error);
  }
}
