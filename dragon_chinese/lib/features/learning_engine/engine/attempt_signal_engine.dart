import 'package:dragon_chinese/features/learning_engine/models/attempt_signal.dart';

class AttemptSignalInput {
  final bool isCorrect;
  final int attemptsUsed;
  final int? latencyMs;
  final String exerciseType;
  final String skill;
  final double? speakingScore;

  const AttemptSignalInput({
    required this.isCorrect,
    required this.attemptsUsed,
    required this.latencyMs,
    required this.exerciseType,
    required this.skill,
    required this.speakingScore,
  });
}

class AttemptSignalEngine {
  const AttemptSignalEngine._();

  static AttemptSignal classify(AttemptSignalInput input) {
    final latency = input.latencyMs;
    final attempts = input.attemptsUsed <= 0 ? 1 : input.attemptsUsed;
    final speakingScore = input.speakingScore;

    final isFastEnough = switch (input.skill) {
      'listening' => latency != null && latency <= 2600,
      'reading' => latency != null && latency <= 3800,
      'characters' => latency != null && latency <= 5000,
      'production' => latency != null && latency <= 5600,
      'speaking' => speakingScore != null && speakingScore >= 0.88,
      _ => latency != null && latency <= 4200,
    };

    final state = _stateFor(
      isCorrect: input.isCorrect,
      attemptsUsed: attempts,
      isFastEnough: isFastEnough,
      skill: input.skill,
      speakingScore: speakingScore,
    );

    return AttemptSignal(
      knowledgeState: state,
      confidence: _confidenceFor(
        state: state,
        attemptsUsed: attempts,
        isFastEnough: isFastEnough,
        speakingScore: speakingScore,
      ),
      isCorrect: input.isCorrect,
      attemptsUsed: attempts,
      latencyMs: latency,
      exerciseType: input.exerciseType,
      skill: input.skill,
      speakingScore: speakingScore,
    );
  }

  static AttemptKnowledgeState _stateFor({
    required bool isCorrect,
    required int attemptsUsed,
    required bool isFastEnough,
    required String skill,
    required double? speakingScore,
  }) {
    if (!isCorrect) return AttemptKnowledgeState.struggling;

    if (skill == 'speaking') {
      if ((speakingScore ?? 0) >= 0.9 && attemptsUsed == 1) {
        return AttemptKnowledgeState.knows;
      }
      return AttemptKnowledgeState.learning;
    }

    if (attemptsUsed == 1 && isFastEnough) return AttemptKnowledgeState.knows;
    if (attemptsUsed >= 3) return AttemptKnowledgeState.struggling;
    return AttemptKnowledgeState.learning;
  }

  static double _confidenceFor({
    required AttemptKnowledgeState state,
    required int attemptsUsed,
    required bool isFastEnough,
    required double? speakingScore,
  }) {
    final base = switch (state) {
      AttemptKnowledgeState.knows => 0.9,
      AttemptKnowledgeState.learning => 0.72,
      AttemptKnowledgeState.struggling => 0.84,
    };

    var v = base;
    if (attemptsUsed > 1) v -= (attemptsUsed - 1) * 0.06;
    if (!isFastEnough) v -= 0.04;
    if (speakingScore != null) {
      v += ((speakingScore - 0.8) * 0.2);
    }
    return v.clamp(0.5, 0.97);
  }
}
