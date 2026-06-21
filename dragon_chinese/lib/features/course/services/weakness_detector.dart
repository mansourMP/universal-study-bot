import 'package:dragon_chinese/features/course/services/mastery_models.dart';
import 'package:dragon_chinese/features/course/services/mastery_store.dart';

/// Identifies weak skills and struggling words for adaptive learning
class WeaknessDetector {
  /// Threshold below which a skill is considered "weak" (0-1 scale)
  static const double weakSkillThreshold = 0.6;

  /// Threshold below which a word is considered "struggling" (accuracy)
  static const double strugglingAccuracyThreshold = 0.5;

  /// Minimum attempts before considering a word for weakness analysis
  static const int minAttemptsForAnalysis = 3;

  /// Analyzes user's mastery data and returns weakness report
  WeaknessReport analyze({
    required MasteryStore mastery,
    required List<int> wordIds,
    required Map<String, double> skillScores, // e.g., {"reading": 0.65}
  }) {
    // 1. Identify weak skills (below 60%)
    final weakSkills = <String, double>{};
    for (final entry in skillScores.entries) {
      if (entry.value < weakSkillThreshold) {
        weakSkills[entry.key] = entry.value;
      }
    }

    // 2. Find struggling words (low accuracy in last attempts)
    final strugglingWords = <StrugglingWord>[];
    for (final wordId in wordIds) {
      for (final skillType in [
        'meaning',
        'character',
        'listening',
        'reading',
        'production',
      ]) {
        final state = mastery.skillStateFor(wordId, skillType);

        // Only analyze if user has attempted this word enough times
        if (state.attemptsTotal >= minAttemptsForAnalysis) {
          final accuracy = state.correctTotal / state.attemptsTotal;

          if (accuracy < strugglingAccuracyThreshold) {
            strugglingWords.add(
              StrugglingWord(
                wordId: wordId,
                skillType: skillType,
                accuracy: accuracy,
                attempts: state.attemptsTotal,
                stage: state.stage,
              ),
            );
          }
        }
      }
    }

    // 3. Sort struggling words by severity (lowest accuracy first)
    strugglingWords.sort((a, b) => a.accuracy.compareTo(b.accuracy));

    // 4. Generate recommendations
    final recommendations = _generateRecommendations(
      weakSkills: weakSkills,
      strugglingWords: strugglingWords,
    );

    return WeaknessReport(
      weakSkills: weakSkills,
      strugglingWords: strugglingWords,
      recommendations: recommendations,
      overallWeaknessScore: _calculateOverallWeakness(weakSkills, skillScores),
    );
  }

  /// Calculates overall weakness score (0-1, higher = more weakness)
  double _calculateOverallWeakness(
    Map<String, double> weakSkills,
    Map<String, double> allSkills,
  ) {
    if (allSkills.isEmpty) return 0.0;

    // Average of how far below threshold each weak skill is
    double totalGap = 0.0;
    for (final entry in weakSkills.entries) {
      totalGap += (weakSkillThreshold - entry.value);
    }

    return totalGap / allSkills.length;
  }

  /// Generates actionable recommendations based on weaknesses
  List<String> _generateRecommendations({
    required Map<String, double> weakSkills,
    required List<StrugglingWord> strugglingWords,
  }) {
    final recommendations = <String>[];

    // Skill-based recommendations
    if (weakSkills.containsKey('reading')) {
      recommendations.add('Practice reading comprehension exercises');
    }
    if (weakSkills.containsKey('listening')) {
      recommendations.add('Focus on audio drills and tone recognition');
    }
    if (weakSkills.containsKey('writing')) {
      recommendations.add('Work on character writing and stroke order');
    }
    if (weakSkills.containsKey('speaking')) {
      recommendations.add('Practice pronunciation and speaking exercises');
    }

    // Word-based recommendations
    if (strugglingWords.length >= 5) {
      final topStruggles = strugglingWords.take(5).toList();
      final skillCounts = <String, int>{};

      for (final word in topStruggles) {
        skillCounts[word.skillType] = (skillCounts[word.skillType] ?? 0) + 1;
      }

      final mostCommonSkill = skillCounts.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;

      recommendations.add(
        'You\'re struggling with $mostCommonSkill - next lessons will focus on this',
      );
    }

    if (recommendations.isEmpty) {
      recommendations.add(
        'Keep up the great work! All skills are progressing well.',
      );
    }

    return recommendations;
  }
}

/// Report of user's weaknesses and recommendations
class WeaknessReport {
  /// Skills below the weakness threshold
  final Map<String, double> weakSkills;

  /// Words with low accuracy
  final List<StrugglingWord> strugglingWords;

  /// Actionable recommendations
  final List<String> recommendations;

  /// Overall weakness score (0-1, higher = more weakness)
  final double overallWeaknessScore;

  WeaknessReport({
    required this.weakSkills,
    required this.strugglingWords,
    required this.recommendations,
    required this.overallWeaknessScore,
  });

  /// Whether user has any significant weaknesses
  bool get hasWeaknesses => weakSkills.isNotEmpty || strugglingWords.isNotEmpty;

  /// Primary recommendation (most important)
  String get primaryRecommendation =>
      recommendations.isNotEmpty ? recommendations.first : 'Keep practicing!';
}

/// A word the user is struggling with
class StrugglingWord {
  final int wordId;
  final String skillType;
  final double accuracy; // 0-1
  final int attempts;
  final SkillStage stage;

  StrugglingWord({
    required this.wordId,
    required this.skillType,
    required this.accuracy,
    required this.attempts,
    required this.stage,
  });

  /// Severity of struggle (0-1, higher = worse)
  double get severity => 1.0 - accuracy;
}
