import 'package:flutter/material.dart';
import 'package:dragon_chinese/core/net/api_result.dart';
import 'package:dragon_chinese/design_system/design_system.dart';

/// Shared UI component that handles loading, error, and empty states.
/// Use this to wrap any screen that fetches remote data.
///
/// Usage:
/// ```dart
/// NetworkStateGate<List<Lesson>>(
///   result: _lessonsResult,
///   isLoading: _isLoading,
///   onRetry: _loadLessons,
///   builder: (data) => LessonList(lessons: data),
/// )
/// ```
class NetworkStateGate<T> extends StatelessWidget {
  /// The API result (success or failure)
  final ApiResult<T>? result;

  /// Whether data is currently loading
  final bool isLoading;

  /// Called when user taps Retry
  final VoidCallback onRetry;

  /// Builder for success state
  final Widget Function(T data) builder;

  /// Optional: check if data is "empty" (e.g., empty list)
  final bool Function(T data)? isEmpty;

  /// Optional: custom empty message
  final String emptyMessage;

  /// Optional: custom loading widget (defaults to skeleton)
  final Widget? loadingWidget;

  const NetworkStateGate({
    super.key,
    required this.result,
    required this.isLoading,
    required this.onRetry,
    required this.builder,
    this.isEmpty,
    this.emptyMessage = 'No content available',
    this.loadingWidget,
  });

  @override
  Widget build(BuildContext context) {
    // Loading state
    if (isLoading && result == null) {
      return loadingWidget ?? const _SkeletonLoader();
    }

    // Error state
    if (result != null && result!.isFailure) {
      final failure = result as ApiFailure<T>;
      return _ErrorCard(
        message: failure.userMessage,
        onRetry: onRetry,
        isRetrying: isLoading,
      );
    }

    // Success state
    if (result != null && result!.isSuccess) {
      final data = (result as ApiSuccess<T>).data;

      // Empty check
      final isDataEmpty = isEmpty?.call(data) ?? _defaultIsEmpty(data);
      if (isDataEmpty) {
        return _EmptyCard(
          message: emptyMessage,
          onRetry: onRetry,
          isRetrying: isLoading,
        );
      }

      return builder(data);
    }

    // Initial state (no result yet)
    return loadingWidget ?? const _SkeletonLoader();
  }

  bool _defaultIsEmpty(T data) {
    if (data is List) return data.isEmpty;
    if (data is Map) return data.isEmpty;
    if (data is Iterable) return data.isEmpty;
    return false;
  }
}

/// Skeleton loader with shimmer effect
class _SkeletonLoader extends StatelessWidget {
  const _SkeletonLoader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SkeletonBox(width: 200, height: 24),
          const SizedBox(height: 16),
          _SkeletonBox(width: double.infinity, height: 80),
          const SizedBox(height: 12),
          _SkeletonBox(width: double.infinity, height: 80),
          const SizedBox(height: 12),
          _SkeletonBox(width: double.infinity, height: 80),
          const SizedBox(height: 12),
          _SkeletonBox(width: 150, height: 20),
        ],
      ),
    );
  }
}

class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;

  const _SkeletonBox({required this.width, required this.height});

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              begin: Alignment(-1 + 2 * _controller.value, 0),
              end: Alignment(1 + 2 * _controller.value, 0),
              colors: [
                AppColors.surface,
                AppColors.surface.withOpacity(0.5),
                AppColors.surface,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Calm error card with retry button
class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool isRetrying;

  const _ErrorCard({
    required this.message,
    required this.onRetry,
    required this.isRetrying,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.error.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.cloud_off_rounded,
                    size: 48,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    style: DragonTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Check your internet connection',
                    style: DragonTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 140,
                    child: ElevatedButton.icon(
                      onPressed: isRetrying ? null : onRetry,
                      icon: isRetrying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(isRetrying ? 'Retrying...' : 'Retry'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state card with retry
class _EmptyCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final bool isRetrying;

  const _EmptyCard({
    required this.message,
    required this.onRetry,
    required this.isRetrying,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_rounded,
              size: 64,
              color: AppColors.textSecondary.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: DragonTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: isRetrying ? null : onRetry,
              icon: isRetrying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: Text(isRetrying ? 'Loading...' : 'Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Standalone error card for use in existing scaffolds
class NetworkErrorCard extends StatelessWidget {
  final ApiFailure failure;
  final VoidCallback onRetry;
  final bool isRetrying;

  const NetworkErrorCard({
    super.key,
    required this.failure,
    required this.onRetry,
    this.isRetrying = false,
  });

  @override
  Widget build(BuildContext context) {
    return _ErrorCard(
      message: failure.userMessage,
      onRetry: onRetry,
      isRetrying: isRetrying,
    );
  }
}
