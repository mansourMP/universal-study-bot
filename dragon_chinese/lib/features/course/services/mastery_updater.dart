import 'package:dragon_chinese/features/course/services/mastery_models.dart';

class MasteryUpdater {
  MasteryUpdater._();

  static SkillMasteryState applyAttempt({
    required SkillMasteryState current,
    required String skill,
    required bool isCorrect,
    required int attemptsUsed,
    required int durationMs,
    required int now,
  }) {
    final delta = _deltaFor(isCorrect, attemptsUsed);
    final nextScore = (current.score + delta).clamp(0.0, 1.0);
    final stage = _stageFor(nextScore);
    final nextAttempts = current.attemptsTotal + 1;
    final nextCorrect =
        current.correctTotal + (isCorrect ? 1 : 0);
    final baseInterval = _baseIntervalMs(skill);
    final interval = isCorrect
        ? (baseInterval * (1.2 + nextScore * 2.0)).round()
        : (baseInterval * 0.45).round();

    return current.copyWith(
      score: nextScore,
      stage: stage,
      lastSeenAt: now,
      dueAt: now + interval,
      attemptsTotal: nextAttempts,
      correctTotal: nextCorrect,
      lastResult: isCorrect,
    );
  }

  static double _deltaFor(bool isCorrect, int attemptsUsed) {
    if (isCorrect) {
      if (attemptsUsed <= 1) return 0.18;
      if (attemptsUsed == 2) return 0.12;
      return 0.08;
    }
    return -0.16;
  }

  static SkillStage _stageFor(double score) {
    if (score < 0.35) return SkillStage.newStage;
    if (score < 0.6) return SkillStage.learning;
    if (score < 0.82) return SkillStage.solid;
    return SkillStage.mastered;
  }

  static int _baseIntervalMs(String skill) {
    switch (skill) {
      case 'meaning':
        return 10 * 60 * 60 * 1000;
      case 'character':
        return 12 * 60 * 60 * 1000;
      case 'listening':
        return 14 * 60 * 60 * 1000;
      case 'reading':
        return 16 * 60 * 60 * 1000;
      case 'production':
        return 12 * 60 * 60 * 1000;
      default:
        return 10 * 60 * 60 * 1000;
    }
  }
}
