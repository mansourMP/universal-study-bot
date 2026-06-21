/// Brain API Models
/// Learning Path 2.0 - Phase 7

class SubjectSkill {
  final String label;
  final String icon;
  final List<String> types;

  SubjectSkill({
    required this.label,
    required this.icon,
    this.types = const [],
  });

  factory SubjectSkill.fromJson(Map<String, dynamic> json) {
    return SubjectSkill(
      label: json['label'] ?? '',
      icon: json['icon'] ?? 'star',
      types: List<String>.from(json['types'] ?? []),
    );
  }
}

class SubjectConfig {
  final String subjectId;
  final String name;
  final Map<String, SubjectSkill> skills;
  final Map<String, dynamic> ui;

  SubjectConfig({
    required this.subjectId,
    required this.name,
    required this.skills,
    required this.ui,
  });

  factory SubjectConfig.fromJson(Map<String, dynamic> json) {
    final skillMap = (json['skills'] as Map<String, dynamic>?) ?? {};
    return SubjectConfig(
      subjectId: json['subject_id'] ?? '',
      name: json['name'] ?? '',
      skills: skillMap.map((k, v) => MapEntry(k, SubjectSkill.fromJson(v))),
      ui: json['ui'] ?? {},
    );
  }

  bool get showPinyinToggle => ui['show_pinyin_toggle'] ?? false;
}

/// A selected exercise from the Brain API with plan_slot semantics.
class BrainExercise {
  final String exerciseId;
  final String wordId;
  final String? senseId;
  final String type;
  final String difficulty;
  final String skillFocus;
  final String stage;
  final String reviewInstanceId;
  final String slotKey;
  final String planSlotId;
  final Map<String, dynamic> payload;
  final String? groupId;

  // Analytics fields (optional)
  final String? selectedBy;
  final bool contentExhausted;

  BrainExercise({
    required this.exerciseId,
    required this.wordId,
    this.senseId,
    required this.type,
    required this.difficulty,
    required this.skillFocus,
    required this.stage,
    required this.reviewInstanceId,
    required this.slotKey,
    required this.planSlotId,
    required this.payload,
    this.groupId,
    this.selectedBy,
    this.contentExhausted = false,
  });

  factory BrainExercise.fromJson(Map<String, dynamic> json) {
    return BrainExercise(
      exerciseId: json['exercise_id'] ?? '',
      wordId: json['word_id'] ?? '',
      senseId: json['sense_id'],
      type: json['type'] ?? 'flashcard',
      difficulty: json['difficulty']?.toString() ?? 'easy',
      skillFocus: json['skill_focus'] ?? 'recognition',
      stage: json['stage']?.toString() ?? 'learn',
      reviewInstanceId: json['review_instance_id'] ?? '',
      slotKey: json['slot_key'] ?? '',
      planSlotId: json['plan_slot_id'] ?? '',
      payload: json['payload'] ?? {},
      groupId: json['group_id'],
      selectedBy: json['selected_by'],
      contentExhausted: json['content_exhausted'] ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'exercise_id': exerciseId,
    'word_id': wordId,
    if (senseId != null) 'sense_id': senseId,
    'type': type,
    'difficulty': difficulty,
    'skill_focus': skillFocus,
    'stage': stage,
    'review_instance_id': reviewInstanceId,
    'slot_key': slotKey,
    'plan_slot_id': planSlotId,
    'payload': payload,
    'group_id': groupId,
  };
}

/// Response from /api/v2/brain/exercises endpoint.
class BrainExercisesResponse {
  final String missionId;
  final List<BrainExercise> exercises;
  final Map<String, dynamic>? metadata;

  BrainExercisesResponse({
    required this.missionId,
    required this.exercises,
    this.metadata,
  });

  factory BrainExercisesResponse.fromJson(Map<String, dynamic> json) {
    final exerciseList = (json['exercises'] as List<dynamic>?) ?? [];
    return BrainExercisesResponse(
      missionId: json['mission_id'] ?? '',
      exercises: exerciseList.map((e) => BrainExercise.fromJson(e)).toList(),
      metadata: json['metadata'],
    );
  }

  Map<String, dynamic>? get scope {
    final meta = metadata;
    if (meta == null) return null;
    final raw = meta['scope'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }

  Map<String, dynamic>? get generation {
    final meta = metadata;
    if (meta == null) return null;
    final raw = meta['generation'];
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return null;
  }
}

/// Request body for /api/v2/brain/submit endpoint.
class BrainSubmitRequest {
  final String userId;
  final String languageCode;
  final String missionId;
  final String exerciseId;
  final String wordId;
  final String? senseId;
  final String planSlotId;
  final bool isCorrect;
  final int? latencyMs;
  final String? idempotencyKey;
  final Map<String, dynamic>? attemptMeta;

  BrainSubmitRequest({
    required this.userId,
    required this.languageCode,
    required this.missionId,
    required this.exerciseId,
    required this.wordId,
    this.senseId,
    required this.planSlotId,
    required this.isCorrect,
    this.latencyMs,
    this.idempotencyKey,
    this.attemptMeta,
  });

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'language_code': languageCode,
    'mission_id': missionId,
    'exercise_id': exerciseId,
    'word_id': wordId,
    if (senseId != null) 'sense_id': senseId,
    'plan_slot_id': planSlotId,
    'is_correct': isCorrect,
    if (latencyMs != null) 'latency_ms': latencyMs,
    if (idempotencyKey != null) 'idempotency_key': idempotencyKey,
    if (attemptMeta != null) 'attempt_meta': attemptMeta,
  };
}

/// Response from /api/v2/brain/submit endpoint.
class BrainSubmitResponse {
  final bool accepted;
  final bool idempotentHit;
  final String? skillUpdated;
  final int? skillScore;
  final int? skillDisplay;
  final String? masteryState;
  final bool stageComplete;
  final int? newStage;
  final List<String> slotsRemaining;
  final String? nextReviewAt;
  final String nextAction;
  final bool? masteryGatePassed;
  final List<String> masteryGateReasons;

  BrainSubmitResponse({
    required this.accepted,
    this.idempotentHit = false,
    this.skillUpdated,
    this.skillScore,
    this.skillDisplay,
    this.masteryState,
    this.stageComplete = false,
    this.newStage,
    this.slotsRemaining = const [],
    this.nextReviewAt,
    this.nextAction = 'continue',
    this.masteryGatePassed,
    this.masteryGateReasons = const [],
  });

  factory BrainSubmitResponse.fromJson(Map<String, dynamic> json) {
    return BrainSubmitResponse(
      accepted: json['accepted'] ?? false,
      idempotentHit: json['idempotent_hit'] ?? false,
      skillUpdated: json['skill_updated'],
      skillScore: json['skill_score'],
      skillDisplay: json['skill_display'],
      masteryState: json['mastery_state'],
      stageComplete: json['stage_complete'] ?? false,
      newStage: json['new_stage'],
      slotsRemaining: List<String>.from(json['slots_remaining'] ?? []),
      nextReviewAt: json['next_review_at'],
      nextAction: json['next_action'] ?? 'continue',
      masteryGatePassed: json['mastery_gate_passed'],
      masteryGateReasons: List<String>.from(json['mastery_gate_reasons'] ?? []),
    );
  }

  /// Whether there are more slots to complete in the current stage.
  bool get hasMoreSlots => slotsRemaining.isNotEmpty;
}

class BrainSummary {
  final int dueCount;
  final int reviewDueCount;
  final int hardDueCount;
  final int softDueCount;
  final int learnAvailableCount;
  final DateTime? nextReviewAt;
  final bool hasActiveMission;
  final String? activeMissionId;
  final DateTime serverTime;

  BrainSummary({
    required this.dueCount,
    required this.reviewDueCount,
    this.hardDueCount = 0,
    this.softDueCount = 0,
    required this.learnAvailableCount,
    this.nextReviewAt,
    required this.hasActiveMission,
    this.activeMissionId,
    required this.serverTime,
  });

  factory BrainSummary.fromJson(Map<String, dynamic> json) {
    return BrainSummary(
      dueCount: json['due_count'] ?? 0,
      reviewDueCount: json['review_due_count'] ?? 0,
      hardDueCount: json['hard_due_count'] ?? 0,
      softDueCount: json['soft_due_count'] ?? 0,
      learnAvailableCount: json['learn_available_count'] ?? 0,
      nextReviewAt: json['next_review_at'] != null
          ? DateTime.tryParse(json['next_review_at'])
          : null,
      hasActiveMission: json['has_active_mission'] ?? false,
      activeMissionId: json['active_mission_id'],
      serverTime: DateTime.parse(json['server_time']),
    );
  }
}
