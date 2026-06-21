/// Brain API Service
/// Learning Path 2.0 - Phase 7.1
///
/// Handles communication with the Brain API for exercise selection and submission.
/// Includes submission cache for idempotency key reuse on retries.

import 'dart:math';
import 'package:dragon_chinese/core/network/api_client.dart';
import 'package:dragon_chinese/features/course/models/brain_models.dart';

/// Cached submission for idempotency reuse on retries.
class SubmissionCache {
  final String idempotencyKey;
  final DateTime createdAt;
  BrainSubmitResponse? lastResponse;
  int retryCount;

  /// Max retries before giving up.
  static const int maxRetries = 5;

  SubmissionCache({
    required this.idempotencyKey,
    DateTime? createdAt,
    this.lastResponse,
    this.retryCount = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  /// Whether this cache entry is stale (older than 10 minutes).
  bool get isStale => DateTime.now().difference(createdAt).inMinutes > 10;

  /// Whether max retries exceeded.
  bool get retriesExceeded => retryCount >= maxRetries;
}

class BrainService {
  final ApiClient _api;
  final Random _random = Random();

  /// Cache keyed by exerciseId:planSlotId for idempotency reuse on retries.
  final Map<String, SubmissionCache> _submissionCache = {};

  /// Max latency before we clamp (e.g., user backgrounded app).
  static const int maxLatencyMs = 60000; // 1 minute

  BrainService({ApiClient? api}) : _api = api ?? ApiClient();

  /// Get subject configuration (skills, UI, etc).
  Future<SubjectConfig> getSubjectConfig({required String subjectId}) async {
    try {
      final data = await _api.getJson('/api/v2/path/config/$subjectId');
      return SubjectConfig.fromJson(data);
    } catch (e) {
      print('Error fetching subject config: $e');
      rethrow;
    }
  }

  /// Get Dashboard Mission Card summary.
  Future<BrainSummary> getSummary({required String userId}) async {
    try {
      final data = await _api.getJson('/api/v2/brain/summary');
      return BrainSummary.fromJson(data);
    } catch (e) {
      print('Error fetching brain summary: $e');
      rethrow;
    }
  }

  /// Start a new mission (replaces getExercises).
  Future<BrainExercisesResponse> startMission({
    required String userId,
    required String languageCode,
    String intent = 'daily', // daily, review, learn
    int? limit,
    int? dailyNewTarget,
    List<String>? forcedIds,
    List<String>? allowedWordIds,
    String? nodeId,
    String? unitId,
    String? focusDimension,
    int? targetMinSeconds,
    int? targetMaxSeconds,
  }) async {
    // Clear stale cache entries on new mission
    _clearStaleCache();

    try {
      final Map<String, dynamic> body = {
        'user_id': userId,
        'intent': intent,
        'language_code': languageCode,
      };
      if (limit != null) {
        body['limit'] = limit;
      }
      if (dailyNewTarget != null) {
        body['daily_new_target'] = dailyNewTarget;
      }
      if (forcedIds != null) {
        body['forced_ids'] = forcedIds;
      }
      if (allowedWordIds != null) {
        body['allowed_word_ids'] = allowedWordIds;
      }
      if (nodeId != null) {
        body['node_id'] = nodeId;
      }
      if (unitId != null) {
        body['unit_id'] = unitId;
      }
      if (focusDimension != null) {
        body['focus_dimension'] = focusDimension;
      }
      if (targetMinSeconds != null) {
        body['target_min_seconds'] = targetMinSeconds;
      }
      if (targetMaxSeconds != null) {
        body['target_max_seconds'] = targetMaxSeconds;
      }

      final data = await _api.postJson('/api/v2/brain/mission', body: body);
      return BrainExercisesResponse.fromJson(data);
    } catch (e) {
      print('Error starting mission: $e');
      rethrow;
    }
  }

  /// RESTORED getExercises for backward compatibility during refactor.
  /// Delegates to startMission.
  Future<BrainExercisesResponse> getExercises({
    required String userId,
    required String languageCode,
    List<String>? wordIds,
    int limit = 5,
    String? missionSeed,
  }) async {
    return startMission(
      userId: userId,
      languageCode: languageCode,
      limit: limit,
    );
  }

  /// Submit an exercise attempt to the Brain API.
  ///
  /// Uses submission cache to reuse the same idempotency key on retries.
  /// This prevents duplicate submissions when network fails.
  Future<BrainSubmitResponse> submitExercise({
    required String userId,
    required String languageCode,
    required String missionId,
    required String exerciseId,
    required String wordId,
    String? senseId,
    required String planSlotId,
    required bool isCorrect,
    int? latencyMs,
    Map<String, dynamic>? attemptMeta,
  }) async {
    // Cache key includes missionId to avoid collision across missions
    final cacheKey = '$missionId:$exerciseId:$planSlotId';

    // Get or create idempotency key (reuse on retry!)
    final cache = _getOrCreateCache(
      cacheKey,
      missionId,
      exerciseId,
      planSlotId,
    );

    // Check if max retries exceeded
    if (cache.retriesExceeded) {
      _submissionCache.remove(cacheKey); // Clear stale cache
      throw Exception(
        'Max retries (${SubmissionCache.maxRetries}) exceeded. Tap to retry.',
      );
    }

    // Clamp latency if too large (user backgrounded app)
    final clampedLatency = latencyMs != null
        ? (latencyMs > maxLatencyMs ? maxLatencyMs : latencyMs)
        : null;

    try {
      final data = await _api.postJson(
        '/api/v2/brain/submit',
        body: {
          'exercise_id': exerciseId,
          'word_id': wordId,
          if (senseId != null) 'sense_id': senseId,
          'is_correct': isCorrect,
          'latency_ms': clampedLatency ?? 0,
          'responseTimeMs': clampedLatency ?? 0,
          'idempotency_key': cache.idempotencyKey,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'user_id': userId,
          'language_code': languageCode,
          'mission_id': missionId,
          'plan_slot_id': planSlotId,
          if (attemptMeta != null && attemptMeta.isNotEmpty)
            'attempt_meta': attemptMeta,
        },
      );

      final response = BrainSubmitResponse.fromJson(data);

      // Cache successful response
      cache.lastResponse = response;

      // Clear cache on ANY success (including idempotent_hit / no-op)
      // Next genuine attempt gets a fresh idempotency key
      _submissionCache.remove(cacheKey);

      return response;
    } catch (e) {
      // Increment retry count but keep same idempotency key
      cache.retryCount++;
      print(
        'Error submitting (retry ${cache.retryCount}/${SubmissionCache.maxRetries}): $e',
      );
      rethrow;
    }
  }

  /// Get cached submission or create new one with stable idempotency key.
  SubmissionCache _getOrCreateCache(
    String cacheKey,
    String missionId,
    String exerciseId,
    String planSlotId,
  ) {
    if (_submissionCache.containsKey(cacheKey)) {
      final existing = _submissionCache[cacheKey]!;
      if (!existing.isStale) {
        return existing;
      }
      // Stale entry, create new one
    }

    // Generate stable idempotency key (no timestamp for reuse!)
    final idemKey = _generateIdempotencyKey(missionId, exerciseId, planSlotId);
    final cache = SubmissionCache(idempotencyKey: idemKey);
    _submissionCache[cacheKey] = cache;
    return cache;
  }

  /// Generate a stable idempotency key for a submission.
  /// Uses random component (generated once and cached) for uniqueness.
  String _generateIdempotencyKey(
    String missionId,
    String exerciseId,
    String planSlotId,
  ) {
    // Random suffix for uniqueness, but stable once generated
    final randomSuffix = _random.nextInt(999999).toString().padLeft(6, '0');
    return '$missionId:$exerciseId:$planSlotId:$randomSuffix';
  }

  /// Clear stale cache entries (older than 5 minutes).
  void _clearStaleCache() {
    _submissionCache.removeWhere((_, cache) => cache.isStale);
  }

  /// Clear all cache (call on session reset).
  void clearCache() {
    _submissionCache.clear();
  }

  /// Generate a new mission ID using timestamp and random.
  String generateMissionId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final randomPart = _random.nextInt(99999).toString().padLeft(5, '0');
    return 'mission_${timestamp}_$randomPart';
  }

  @Deprecated(
    'No backend /api/v2/brain/word route exists. Use vocabulary endpoints instead.',
  )
  /// Disabled legacy path to avoid calling a non-existent backend route.
  Future<Map<String, dynamic>> getWordDetails(int conceptId) async {
    throw UnsupportedError(
      'getWordDetails is disabled: /api/v2/brain/word/$conceptId is not implemented on backend.',
    );
  }
}
