enum AttemptKnowledgeState { knows, learning, struggling }

extension AttemptKnowledgeStateWire on AttemptKnowledgeState {
  String get wireName {
    switch (this) {
      case AttemptKnowledgeState.knows:
        return 'knows';
      case AttemptKnowledgeState.learning:
        return 'learning';
      case AttemptKnowledgeState.struggling:
        return 'struggling';
    }
  }
}

class AttemptSignal {
  final AttemptKnowledgeState knowledgeState;
  final double confidence;
  final bool isCorrect;
  final int attemptsUsed;
  final int? latencyMs;
  final String exerciseType;
  final String skill;
  final double? speakingScore;

  const AttemptSignal({
    required this.knowledgeState,
    required this.confidence,
    required this.isCorrect,
    required this.attemptsUsed,
    required this.latencyMs,
    required this.exerciseType,
    required this.skill,
    required this.speakingScore,
  });

  Map<String, dynamic> toJson() => {
    'knowledge_state': knowledgeState.wireName,
    'confidence': confidence,
    'is_correct': isCorrect,
    'attempts_used': attemptsUsed,
    if (latencyMs != null) 'latency_ms': latencyMs,
    'exercise_type': exerciseType,
    'skill': skill,
    if (speakingScore != null) 'speaking_score': speakingScore,
  };
}
