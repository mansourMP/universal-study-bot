import 'dart:convert';

class SkillState {
  final double strength;
  final int dueAt;
  final int lastSeen;
  final int streak;
  final int lapses;

  const SkillState({
    required this.strength,
    required this.dueAt,
    required this.lastSeen,
    required this.streak,
    required this.lapses,
  });

  factory SkillState.initial() {
    return const SkillState(
      strength: 0.25,
      dueAt: 0,
      lastSeen: 0,
      streak: 0,
      lapses: 0,
    );
  }

  SkillState copyWith({
    double? strength,
    int? dueAt,
    int? lastSeen,
    int? streak,
    int? lapses,
  }) {
    return SkillState(
      strength: strength ?? this.strength,
      dueAt: dueAt ?? this.dueAt,
      lastSeen: lastSeen ?? this.lastSeen,
      streak: streak ?? this.streak,
      lapses: lapses ?? this.lapses,
    );
  }

  Map<String, dynamic> toJson() => {
        'strength': strength,
        'due_at': dueAt,
        'last_seen': lastSeen,
        'streak': streak,
        'lapses': lapses,
      };

  factory SkillState.fromJson(Map<String, dynamic> json) {
    return SkillState(
      strength: (json['strength'] ?? 0.25).toDouble(),
      dueAt: json['due_at'] ?? 0,
      lastSeen: json['last_seen'] ?? 0,
      streak: json['streak'] ?? 0,
      lapses: json['lapses'] ?? 0,
    );
  }
}

class ConceptSkillState {
  final int wordId;
  final Map<String, SkillState> skills;

  ConceptSkillState({required this.wordId, required this.skills});

  SkillState skill(String key) => skills[key] ?? SkillState.initial();

  ConceptSkillState copyWithSkill(String key, SkillState state) {
    final updated = Map<String, SkillState>.from(skills);
    updated[key] = state;
    return ConceptSkillState(wordId: wordId, skills: updated);
  }

  Map<String, dynamic> toJson() => {
        'word_id': wordId,
        'skills': skills.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory ConceptSkillState.fromJson(Map<String, dynamic> json) {
    final rawSkills = (json['skills'] as Map<String, dynamic>? ?? {});
    final parsed = <String, SkillState>{};
    for (final entry in rawSkills.entries) {
      if (entry.value is Map<String, dynamic>) {
        parsed[entry.key] = SkillState.fromJson(entry.value);
      }
    }
    return ConceptSkillState(
      wordId: json['word_id'] ?? 0,
      skills: parsed,
    );
  }
}

class AttemptEvent {
  final int wordId;
  final String exerciseType;
  final String skill;
  final bool isCorrect;
  final int attemptsUsed;
  final int durationMs;
  final int timestamp;
  final String? selfRating;

  AttemptEvent({
    required this.wordId,
    required this.exerciseType,
    required this.skill,
    required this.isCorrect,
    required this.attemptsUsed,
    required this.durationMs,
    required this.timestamp,
    this.selfRating,
  });

  Map<String, dynamic> toJson() => {
        'word_id': wordId,
        'exercise_type': exerciseType,
        'skill': skill,
        'is_correct': isCorrect,
        'attempts_used': attemptsUsed,
        'duration_ms': durationMs,
        'timestamp': timestamp,
        'self_rating': selfRating,
      };
}

class SkillTrend {
  final int consecutiveIncorrect;
  final int consecutiveCorrectFast;
  final int lastLatencyMs;

  const SkillTrend({
    required this.consecutiveIncorrect,
    required this.consecutiveCorrectFast,
    required this.lastLatencyMs,
  });

  factory SkillTrend.initial() {
    return const SkillTrend(
      consecutiveIncorrect: 0,
      consecutiveCorrectFast: 0,
      lastLatencyMs: 0,
    );
  }

  SkillTrend copyWith({
    int? consecutiveIncorrect,
    int? consecutiveCorrectFast,
    int? lastLatencyMs,
  }) {
    return SkillTrend(
      consecutiveIncorrect: consecutiveIncorrect ?? this.consecutiveIncorrect,
      consecutiveCorrectFast:
          consecutiveCorrectFast ?? this.consecutiveCorrectFast,
      lastLatencyMs: lastLatencyMs ?? this.lastLatencyMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'consecutive_incorrect': consecutiveIncorrect,
        'consecutive_correct_fast': consecutiveCorrectFast,
        'last_latency_ms': lastLatencyMs,
      };

  factory SkillTrend.fromJson(Map<String, dynamic> json) {
    return SkillTrend(
      consecutiveIncorrect: json['consecutive_incorrect'] ?? 0,
      consecutiveCorrectFast: json['consecutive_correct_fast'] ?? 0,
      lastLatencyMs: json['last_latency_ms'] ?? 0,
    );
  }
}

class PracticeSessionItem {
  final String id;
  final int wordId;
  final String exerciseType;
  final String skill;
  final int level;
  final String why;
  final List<String> reasonCodes;
  final Map<String, dynamic> meta;

  PracticeSessionItem({
    required this.id,
    required this.wordId,
    required this.exerciseType,
    required this.skill,
    required this.level,
    required this.why,
    this.reasonCodes = const [],
    required this.meta,
  });
}

class PracticeSessionSection {
  final String label;
  final List<PracticeSessionItem> items;

  PracticeSessionSection({required this.label, required this.items});
}

class PracticeSessionPlan {
  final String seed;
  final String dateBucket;
  final List<PracticeSessionSection> sections;
  final List<PracticeSessionItem> items;

  PracticeSessionPlan({
    required this.seed,
    required this.dateBucket,
    required this.sections,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'seed': seed,
        'date_bucket': dateBucket,
        'items': items
            .map(
              (item) => {
                'id': item.id,
                'word_id': item.wordId,
                'exercise_type': item.exerciseType,
                'skill': item.skill,
                'level': item.level,
                'why': item.why,
                'reason_codes': item.reasonCodes,
                'meta': item.meta,
              },
            )
            .toList(),
      };

  String toRawJson() => jsonEncode(toJson());
}

class PracticeSchedulerConfig {
  final int totalCount;
  final Map<String, int> skillWeights;
  final bool overrideGoalWeights;

  const PracticeSchedulerConfig({
    this.totalCount = 16,
    this.skillWeights = const {
      'meaning': 25,
      'characters': 20,
      'pinyin': 15,
      'listening': 15,
      'reading': 15,
      'production': 10,
    },
    this.overrideGoalWeights = false,
  });
}
