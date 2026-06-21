/// Brain Exercise Controller
/// Learning Path 2.0 - Phase 7.1
///
/// Manages exercise flow with plan_slot semantics, stage completion tracking,
/// and skill updates. Slot tracking is per-word for multi-word missions.

import 'package:flutter/foundation.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/features/course/engine/practice_exercise_engine.dart';
import 'package:dragon_chinese/features/course/models/brain_models.dart';
import 'package:dragon_chinese/features/course/services/brain_service.dart';

/// State of the current exercise session.
enum SessionState { loading, ready, submitting, stageComplete, error }

/// Slot progress for a specific word in a stage.
class WordSlotProgress {
  final String wordId;
  final String reviewInstanceId;
  final String stage;
  final Set<String> requiredSlots;
  final Set<String> passedSlots;

  WordSlotProgress({
    required this.wordId,
    required this.reviewInstanceId,
    required this.stage,
    required this.requiredSlots,
    Set<String>? passedSlots,
  }) : passedSlots = passedSlots ?? {};

  Set<String> get remainingSlots => requiredSlots.difference(passedSlots);
  bool get isComplete => requiredSlots.isNotEmpty && remainingSlots.isEmpty;

  WordSlotProgress copyWith({Set<String>? passedSlots}) {
    return WordSlotProgress(
      wordId: wordId,
      reviewInstanceId: reviewInstanceId,
      stage: stage,
      requiredSlots: requiredSlots,
      passedSlots: passedSlots ?? this.passedSlots,
    );
  }
}

/// Manages a Brain exercise session with plan_slot semantics.
class BrainExerciseController extends ChangeNotifier {
  final BrainService _brainService;

  // Session state
  SessionState _state = SessionState.loading;
  String? _errorMessage;

  // Mission data
  String? _missionId;
  SubjectConfig? _config;
  Map<String, dynamic>? _missionMetadata;
  List<BrainExercise> _exercises = [];
  int _currentIndex = 0;

  // Per-word slot tracking: key = "{wordId}:{reviewInstanceId}"
  final Map<String, WordSlotProgress> _wordProgress = {};

  // Timing: per exercise, reset on each exercise
  DateTime? _exerciseStartTime;

  // Last submit response (for UI feedback)
  BrainSubmitResponse? _lastResponse;

  // Getters
  SessionState get state => _state;
  String? get errorMessage => _errorMessage;
  String? get missionId => _missionId;
  SubjectConfig? get config => _config;
  Map<String, dynamic>? get missionMetadata => _missionMetadata;
  int get ringSlots {
    final metadata = _missionMetadata;
    if (metadata == null) return 7;

    int parse(dynamic value, int fallback) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? fallback;
      if (value is double) return value.round();
      return fallback;
    }

    final topLevel = parse(metadata['ring_slots'], -1);
    if (topLevel >= 3 && topLevel <= 8) return topLevel;

    final pack = metadata['hsk1_pack'];
    if (pack is Map) {
      final nested = parse(pack['ring_slots'], -1);
      if (nested >= 3 && nested <= 8) return nested;
    }
    return 7;
  }

  List<BrainExercise> get exercises => _exercises;
  int get currentIndex => _currentIndex;
  BrainExercise? get currentExercise =>
      _currentIndex < _exercises.length ? _exercises[_currentIndex] : null;

  double get progress =>
      _exercises.isEmpty ? 0 : (_currentIndex + 1) / _exercises.length;

  int get exercisesCompleted => _currentIndex;
  int get exercisesTotal => _exercises.length;

  BrainSubmitResponse? get lastResponse => _lastResponse;
  String? get lastSkillUpdated => _lastResponse?.skillUpdated;
  int? get lastSkillScore => _lastResponse?.skillScore;
  int? get lastSkillDisplay => _lastResponse?.skillDisplay;
  String? get lastMasteryState => _lastResponse?.masteryState;
  String? get nextReviewAt => _lastResponse?.nextReviewAt;
  int? get currentLatencyMs => _exerciseStartTime == null
      ? null
      : DateTime.now().difference(_exerciseStartTime!).inMilliseconds;

  /// Get slot progress for the current exercise's word.
  WordSlotProgress? get currentWordProgress {
    final ex = currentExercise;
    if (ex == null) return null;
    return _wordProgress[_wordKey(ex.wordId, ex.reviewInstanceId)];
  }

  BrainExerciseController({BrainService? brainService})
    : _brainService = brainService ?? BrainService();

  String _wordKey(String wordId, String reviewInstanceId) =>
      '$wordId:$reviewInstanceId';

  /// Start a new exercise session.
  Future<void> startSession({
    String intent = 'daily',
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
    _state = SessionState.loading;
    _errorMessage = null;
    _missionMetadata = null;
    _wordProgress.clear();
    _brainService.clearCache(); // Clear submission cache on new session
    notifyListeners();

    try {
      final effectiveAllowedWordIds =
          (allowedWordIds == null || allowedWordIds.isEmpty)
          ? forcedIds
          : allowedWordIds;
      final response = await _brainService.startMission(
        userId: AppConfig.userId,
        languageCode: AppConfig.targetLang,
        intent: intent,
        limit: limit,
        dailyNewTarget: dailyNewTarget,
        forcedIds: forcedIds,
        allowedWordIds: effectiveAllowedWordIds,
        nodeId: nodeId,
        unitId: unitId,
        focusDimension: focusDimension,
        targetMinSeconds: targetMinSeconds,
        targetMaxSeconds: targetMaxSeconds,
      );

      _config = await _brainService.getSubjectConfig(
        subjectId: AppConfig.subjectId,
      );

      _missionId = response.missionId;
      _missionMetadata = response.metadata;
      _exercises = response.exercises
          .where(
            (exercise) =>
                PracticeExerciseEngine.isSessionEnabledType(exercise.type),
          )
          .toList(growable: false);
      if (kDebugMode && _exercises.length != response.exercises.length) {
        final filtered = response.exercises.length - _exercises.length;
        debugPrint(
          '[BrainExerciseController] Filtered $filtered disabled exercise type(s): '
          '${PracticeExerciseEngine.temporarilyDisabledTypes().join(', ')}',
        );
      }

      if (_exercises.isEmpty) {
        _state = SessionState.error;
        _errorMessage =
            'No active exercises available in this mission. Please retry.';
        notifyListeners();
        return;
      }
      _currentIndex = 0;
      _lastResponse = null;

      // Build per-word slot progress
      _buildWordProgress();

      // Start timing for first exercise
      _exerciseStartTime = DateTime.now();

      _state = SessionState.ready;
      notifyListeners();
    } catch (e) {
      _state = SessionState.error;
      _errorMessage = e.toString();
      notifyListeners();
    }
  }

  /// Build slot progress tracking per word.
  void _buildWordProgress() {
    for (final ex in _exercises) {
      final key = _wordKey(ex.wordId, ex.reviewInstanceId);
      if (!_wordProgress.containsKey(key)) {
        _wordProgress[key] = WordSlotProgress(
          wordId: ex.wordId,
          reviewInstanceId: ex.reviewInstanceId,
          stage: ex.stage,
          requiredSlots: {},
        );
      }
      // Add this exercise's slot to required slots
      _wordProgress[key]!.requiredSlots.add(ex.slotKey);
    }
  }

  /// Check if the given answer is correct for the current exercise.
  bool isCorrect(String? selectedAnswer) {
    final ex = currentExercise;
    if (ex == null) return false;

    // Check against payload.answer (backend provides this)
    final correctAnswer = ex.payload['answer']?.toString();
    return selectedAnswer == correctAnswer;
  }

  /// Submit the current exercise result.
  /// Returns the response or null on error.
  Future<BrainSubmitResponse?> submitAnswer({
    required bool isCorrect,
    Map<String, dynamic>? attemptMeta,
  }) async {
    final ex = currentExercise;
    if (ex == null || _missionId == null) return null;

    // Calculate latency from when THIS exercise was shown
    final latencyMs = _exerciseStartTime != null
        ? DateTime.now().difference(_exerciseStartTime!).inMilliseconds
        : null;

    _state = SessionState.submitting;
    notifyListeners();

    try {
      final response = await _brainService.submitExercise(
        userId: AppConfig.userId,
        languageCode: AppConfig.targetLang,
        missionId: _missionId!,
        exerciseId: ex.exerciseId,
        wordId: ex.wordId,
        senseId: ex.senseId,
        planSlotId: ex.planSlotId, // Pass opaquely, don't parse
        isCorrect: isCorrect,
        latencyMs: latencyMs,
        attemptMeta: attemptMeta,
      );

      // Store full response for UI
      _lastResponse = response;

      // Update per-word slot tracking
      if (isCorrect) {
        final key = _wordKey(ex.wordId, ex.reviewInstanceId);
        final progress = _wordProgress[key];
        if (progress != null) {
          progress.passedSlots.add(ex.slotKey);
        }
      }

      // Stage completion is word-level, not mission-level.
      // Keep the mission running unless exercises are exhausted.
      if (response.stageComplete) {
        _handleStageComplete(ex, response);
      }
      _state = SessionState.ready;

      notifyListeners();
      return response;
    } catch (e) {
      _state = SessionState.error;
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Handle stage completion: clear local state for this word's stage.
  void _handleStageComplete(BrainExercise ex, BrainSubmitResponse response) {
    final key = _wordKey(ex.wordId, ex.reviewInstanceId);

    // Clear this word's slot progress (stage is complete)
    _wordProgress.remove(key);

    // The new stage info comes from server response
    // No client-side stage logic needed
  }

  /// Move to the next exercise.
  bool nextExercise() {
    if (_currentIndex + 1 < _exercises.length) {
      _currentIndex++;
      // Reset timing for NEW exercise
      _exerciseStartTime = DateTime.now();
      _state = SessionState.ready;
      _lastResponse = null; // Clear last response for new exercise
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Check if there are more exercises in the session.
  bool get hasMoreExercises => _currentIndex + 1 < _exercises.length;

  /// Get all remaining slots across all words in this mission.
  Map<String, Set<String>> get allRemainingSlotsByWord {
    return Map.fromEntries(
      _wordProgress.entries
          .where((e) => e.value.remainingSlots.isNotEmpty)
          .map((e) => MapEntry(e.key, e.value.remainingSlots)),
    );
  }

  /// Reset the controller for a new session.
  void reset() {
    _state = SessionState.loading;
    _errorMessage = null;
    _missionId = null;
    _missionMetadata = null;
    _exercises = [];
    _currentIndex = 0;
    _wordProgress.clear();
    _exerciseStartTime = null;
    _lastResponse = null;
    _brainService.clearCache();
    notifyListeners();
  }
}
