import 'dart:math';

import 'package:dragon_chinese/core/utils/event_tracker.dart';

enum ExerciseRunner { brain, practice, exam }

extension ExerciseRunnerWire on ExerciseRunner {
  String get wireName {
    switch (this) {
      case ExerciseRunner.brain:
        return 'brain';
      case ExerciseRunner.practice:
        return 'practice';
      case ExerciseRunner.exam:
        return 'exam';
    }
  }
}

class ExerciseAnalyticsContext {
  final String sessionId;
  final ExerciseRunner runner;
  final String exerciseId;
  final String exerciseType;
  final String? skill;
  final int index;
  final int total;
  final int? attemptsRemaining;
  final int? attemptsAllowed;
  final int? subStepIndex;

  const ExerciseAnalyticsContext({
    required this.sessionId,
    required this.runner,
    required this.exerciseId,
    required this.exerciseType,
    required this.index,
    required this.total,
    this.skill,
    this.attemptsRemaining,
    this.attemptsAllowed,
    this.subStepIndex,
  });

  Map<String, Object?> toParams() {
    return <String, Object?>{
      'session_id': sessionId,
      'runner': runner.wireName,
      'exercise_id': exerciseId,
      'exercise_type': exerciseType,
      'skill': skill,
      'index': index,
      'total': total,
      'attempts_remaining': attemptsRemaining,
      'attempts_allowed': attemptsAllowed,
      'sub_step_index': subStepIndex,
    };
  }
}

class ExerciseAnalytics {
  static String newSessionId(ExerciseRunner runner) {
    final micros = DateTime.now().microsecondsSinceEpoch;
    final salt = Random(micros ^ runner.hashCode).nextInt(1 << 20);
    return '${runner.wireName}_${micros}_${salt.toRadixString(16)}';
  }

  static void sessionStarted({
    required String sessionId,
    required ExerciseRunner runner,
    required int totalExercises,
    String? missionId,
    String? seed,
  }) {
    _track('exercise_session_started', {
      'session_id': sessionId,
      'runner': runner.wireName,
      'total_exercises': totalExercises,
      'mission_id': missionId,
      'seed': seed,
    });
  }

  static void exerciseShown(
    ExerciseAnalyticsContext context, {
    String? source,
  }) {
    _track('exercise_shown', {...context.toParams(), 'source': source});
  }

  static void interacted(
    ExerciseAnalyticsContext context, {
    required String interaction,
  }) {
    _track('exercise_interacted', {
      ...context.toParams(),
      'interaction': interaction,
    });
  }

  static void checkTapped(ExerciseAnalyticsContext context) {
    _track('exercise_check_tapped', context.toParams());
  }

  static void result(
    ExerciseAnalyticsContext context, {
    required bool isCorrect,
    required bool finalized,
    int? latencyMs,
    int? attemptsUsed,
    String? knowledgeState,
  }) {
    _track('exercise_result', {
      ...context.toParams(),
      'is_correct': isCorrect,
      'finalized': finalized,
      'latency_ms': latencyMs,
      'attempts_used': attemptsUsed,
      'knowledge_state': knowledgeState,
    });
  }

  static void tryAgain(ExerciseAnalyticsContext context) {
    _track('exercise_try_again', context.toParams());
  }

  static void continued(ExerciseAnalyticsContext context) {
    _track('exercise_continue', context.toParams());
  }

  static void skipped(
    ExerciseAnalyticsContext context, {
    required String reason,
  }) {
    _track('exercise_skipped', {...context.toParams(), 'reason': reason});
  }

  static void sessionCompleted({
    required String sessionId,
    required ExerciseRunner runner,
    required int totalExercises,
    required int completedExercises,
    int? correctExercises,
    int? durationMs,
  }) {
    _track('exercise_session_completed', {
      'session_id': sessionId,
      'runner': runner.wireName,
      'total_exercises': totalExercises,
      'completed_exercises': completedExercises,
      'correct_exercises': correctExercises,
      'duration_ms': durationMs,
    });
  }

  static void sessionQuit({
    required String sessionId,
    required ExerciseRunner runner,
    required int totalExercises,
    required int completedExercises,
    int? durationMs,
  }) {
    _track('exercise_session_quit', {
      'session_id': sessionId,
      'runner': runner.wireName,
      'total_exercises': totalExercises,
      'completed_exercises': completedExercises,
      'duration_ms': durationMs,
    });
  }

  static void _track(String eventName, Map<String, Object?> params) {
    final compact = <String, Object?>{};
    for (final entry in params.entries) {
      final value = entry.value;
      if (value != null) {
        compact[entry.key] = value;
      }
    }
    EventTracker.track(eventName, params: compact);
  }
}
