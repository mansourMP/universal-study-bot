enum SkillStage { newStage, learning, solid, mastered }

class SkillMasteryState {
  final double score;
  final SkillStage stage;
  final int lastSeenAt;
  final int dueAt;
  final int attemptsTotal;
  final int correctTotal;
  final bool lastResult;

  const SkillMasteryState({
    required this.score,
    required this.stage,
    required this.lastSeenAt,
    required this.dueAt,
    required this.attemptsTotal,
    required this.correctTotal,
    required this.lastResult,
  });

  factory SkillMasteryState.initial() {
    return const SkillMasteryState(
      score: 0.2,
      stage: SkillStage.newStage,
      lastSeenAt: 0,
      dueAt: 0,
      attemptsTotal: 0,
      correctTotal: 0,
      lastResult: false,
    );
  }

  SkillMasteryState copyWith({
    double? score,
    SkillStage? stage,
    int? lastSeenAt,
    int? dueAt,
    int? attemptsTotal,
    int? correctTotal,
    bool? lastResult,
  }) {
    return SkillMasteryState(
      score: score ?? this.score,
      stage: stage ?? this.stage,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      dueAt: dueAt ?? this.dueAt,
      attemptsTotal: attemptsTotal ?? this.attemptsTotal,
      correctTotal: correctTotal ?? this.correctTotal,
      lastResult: lastResult ?? this.lastResult,
    );
  }

  Map<String, dynamic> toJson() => {
        'score': score,
        'stage': stage.name,
        'last_seen_at': lastSeenAt,
        'due_at': dueAt,
        'attempts_total': attemptsTotal,
        'correct_total': correctTotal,
        'last_result': lastResult,
      };

  factory SkillMasteryState.fromJson(Map<String, dynamic> json) {
    final stageRaw = json['stage']?.toString() ?? 'newStage';
    final stage = SkillStage.values.firstWhere(
      (e) => e.name == stageRaw,
      orElse: () => SkillStage.newStage,
    );
    return SkillMasteryState(
      score: (json['score'] ?? 0.2).toDouble(),
      stage: stage,
      lastSeenAt: json['last_seen_at'] ?? 0,
      dueAt: json['due_at'] ?? 0,
      attemptsTotal: json['attempts_total'] ?? 0,
      correctTotal: json['correct_total'] ?? 0,
      lastResult: json['last_result'] ?? false,
    );
  }
}

class WordSkillMastery {
  final int wordId;
  final Map<String, SkillMasteryState> skills;

  WordSkillMastery({required this.wordId, required this.skills});

  SkillMasteryState skill(String key) =>
      skills[key] ?? SkillMasteryState.initial();

  WordSkillMastery copyWithSkill(String key, SkillMasteryState state) {
    final updated = Map<String, SkillMasteryState>.from(skills);
    updated[key] = state;
    return WordSkillMastery(wordId: wordId, skills: updated);
  }

  Map<String, dynamic> toJson() => {
        'word_id': wordId,
        'skills': skills.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory WordSkillMastery.fromJson(Map<String, dynamic> json) {
    final rawSkills = (json['skills'] as Map<String, dynamic>? ?? {});
    final parsed = <String, SkillMasteryState>{};
    for (final entry in rawSkills.entries) {
      if (entry.value is Map<String, dynamic>) {
        parsed[entry.key] = SkillMasteryState.fromJson(entry.value);
      }
    }
    return WordSkillMastery(
      wordId: json['word_id'] ?? 0,
      skills: parsed,
    );
  }
}
