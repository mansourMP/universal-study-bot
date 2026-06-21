import 'package:dragon_chinese/features/course/services/weakness_detector.dart';

/// Generates adaptive hints for the PATH view based on user weaknesses
class AdaptiveHintGenerator {
  /// Generates a hint message for the next lesson based on weakness report
  static String generateHint(WeaknessReport report, {String? nextLessonFocus}) {
    if (!report.hasWeaknesses) {
      return '🎯 Great progress! Keep up the momentum!';
    }

    // If we know what the next lesson focuses on, tailor the message
    if (nextLessonFocus != null &&
        report.weakSkills.containsKey(nextLessonFocus)) {
      final percentage = (report.weakSkills[nextLessonFocus]! * 100).round();
      return '💡 Your $nextLessonFocus is at $percentage% - this lesson will help!';
    }

    // Generic hint based on primary weakness
    if (report.weakSkills.isNotEmpty) {
      final weakestSkill = report.weakSkills.entries.reduce(
        (a, b) => a.value < b.value ? a : b,
      );
      final percentage = (weakestSkill.value * 100).round();

      return '📚 Focus area: ${weakestSkill.key} ($percentage%) - next 3 lessons target this';
    }

    // Word-based hint
    if (report.strugglingWords.isNotEmpty) {
      final topStruggle = report.strugglingWords.first;
      return '🎓 Struggling with ${topStruggle.skillType}? We\'ll practice this more!';
    }

    return report.primaryRecommendation;
  }

  /// Generates a motivational message based on progress
  static String generateMotivation(WeaknessReport report) {
    if (report.overallWeaknessScore < 0.1) {
      return '🌟 Excellent! You\'re mastering everything!';
    } else if (report.overallWeaknessScore < 0.3) {
      return '💪 Good progress! A few more practice sessions and you\'ll be solid!';
    } else if (report.overallWeaknessScore < 0.5) {
      return '📈 Keep going! Consistency is key to improvement!';
    } else {
      return '🎯 Let\'s focus on building a strong foundation!';
    }
  }

  /// Generates a short summary for dashboard
  static String generateDashboardSummary(WeaknessReport report) {
    if (!report.hasWeaknesses) {
      return 'All skills progressing well';
    }

    if (report.weakSkills.length == 1) {
      final skill = report.weakSkills.keys.first;
      return 'Focus on $skill';
    }

    if (report.weakSkills.length > 1) {
      final skills = report.weakSkills.keys.take(2).join(' & ');
      return 'Practice $skills';
    }

    return 'Keep practicing';
  }
}
