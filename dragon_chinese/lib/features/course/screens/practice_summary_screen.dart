import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/exercise_theme.dart';

class PracticeAttempt {
  final String skill;
  final bool isCorrect;
  final int latencyMs;
  final String? knowledgeState;

  PracticeAttempt({
    required this.skill,
    required this.isCorrect,
    this.latencyMs = 0,
    this.knowledgeState,
  });
}

class PracticeSummaryScreen extends StatelessWidget {
  final List<PracticeAttempt> attempts;
  final VoidCallback? onDrillAgain;
  final VoidCallback? onFixMistakes;
  final VoidCallback? onWeakSkillDrill;
  final VoidCallback? onFinish;
  final String title;

  const PracticeSummaryScreen({
    super.key,
    required this.attempts,
    this.onDrillAgain,
    this.onFixMistakes,
    this.onWeakSkillDrill,
    this.onFinish,
    this.title = 'Practice Summary',
  });

  @override
  Widget build(BuildContext context) {
    final stats = _buildSkillStats();
    final knowledgeStats = _buildKnowledgeStats();
    final accuracy = _overallAccuracy(stats);
    final weakest = _weakestSkills(stats);

    return Scaffold(
      backgroundColor: ExerciseThemeTokens.background,
      appBar: AppBar(
        title: Text(
          title,
          style: ExerciseThemeTokens.promptTitle.copyWith(
            color: ExerciseThemeTokens.textPrimary,
          ),
        ),
        backgroundColor: ExerciseThemeTokens.surface,
        foregroundColor: ExerciseThemeTokens.textPrimary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: ExerciseThemeTokens.border, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(ExerciseThemeTokens.pageMargin),
        children: [
          _buildMetricCard(
            label: 'Accuracy',
            value: '${(accuracy * 100).round()}%',
            subtitle: 'Based on this practice session',
          ),
          if (knowledgeStats.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildKnowledgeCard(knowledgeStats),
          ],
          const SizedBox(height: 24),
          _sectionTitle('Weak skills'),
          const SizedBox(height: 12),
          if (weakest.isEmpty)
            const Text(
              'No weak skills detected.',
              style: ExerciseThemeTokens.promptBody,
            )
          else
            ...weakest.map((skill) => _skillRow(skill, stats[skill]!)),
          const SizedBox(height: 24),
          _sectionTitle('Skill breakdown'),
          const SizedBox(height: 12),
          ...stats.entries.map((entry) => _skillRow(entry.key, entry.value)),
          const SizedBox(height: 32),
          _actionButtons(),
        ],
      ),
    );
  }

  Map<String, _StatLine> _buildSkillStats() {
    final map = <String, _StatLine>{};
    for (final attempt in attempts) {
      map.putIfAbsent(attempt.skill, () => _StatLine());
      map[attempt.skill]!.add(attempt.isCorrect, attempt.latencyMs);
    }
    return map;
  }

  Map<String, int> _buildKnowledgeStats() {
    final map = <String, int>{};
    for (final attempt in attempts) {
      final state = attempt.knowledgeState?.trim().toLowerCase();
      if (state == null || state.isEmpty) continue;
      map[state] = (map[state] ?? 0) + 1;
    }
    return map;
  }

  double _overallAccuracy(Map<String, _StatLine> stats) {
    if (stats.isEmpty) return 0.0;
    int correct = 0;
    int total = 0;
    for (final stat in stats.values) {
      correct += stat.correct;
      total += stat.total;
    }
    return total == 0 ? 0.0 : correct / total;
  }

  List<String> _weakestSkills(Map<String, _StatLine> stats) {
    final entries = stats.entries.toList();
    entries.sort((a, b) => a.value.accuracy.compareTo(b.value.accuracy));
    return entries.take(2).map((e) => e.key).toList();
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ExerciseThemeTokens.surface,
        borderRadius: BorderRadius.circular(ExerciseThemeTokens.cardRadius),
        border: Border.all(color: ExerciseThemeTokens.border),
        boxShadow: [ExerciseThemeTokens.shadowSm],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: ExerciseThemeTokens.caption),
          const SizedBox(height: 8),
          Text(value, style: ExerciseThemeTokens.displayNumber),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: ExerciseThemeTokens.caption.copyWith(
              color: ExerciseThemeTokens.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKnowledgeCard(Map<String, int> knowledgeStats) {
    final knows = knowledgeStats['knows'] ?? 0;
    final learning = knowledgeStats['learning'] ?? 0;
    final struggling = knowledgeStats['struggling'] ?? 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ExerciseThemeTokens.surface,
        borderRadius: BorderRadius.circular(ExerciseThemeTokens.cardRadius),
        border: Border.all(color: ExerciseThemeTokens.border),
      ),
      child: Row(
        children: [
          _knowledgePill('Knows', knows, const Color(0xFF0F9D58)),
          const SizedBox(width: 8),
          _knowledgePill('Learning', learning, const Color(0xFF2563EB)),
          const SizedBox(width: 8),
          _knowledgePill('Struggling', struggling, const Color(0xFFE11D48)),
        ],
      ),
    );
  }

  Widget _knowledgePill(String label, int value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.22)),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: ExerciseThemeTokens.chipText.copyWith(color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: ExerciseThemeTokens.caption.copyWith(color: color),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text, style: ExerciseThemeTokens.promptTitle);
  }

  Widget _skillRow(String skill, _StatLine stat) {
    final accuracy = stat.total == 0 ? 0.0 : stat.correct / stat.total;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: ExerciseThemeTokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ExerciseThemeTokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _labelForSkill(skill),
              style: ExerciseThemeTokens.label.copyWith(
                color: ExerciseThemeTokens.textPrimary,
              ),
            ),
          ),
          Text(
            '${(accuracy * 100).round()}%',
            style: ExerciseThemeTokens.chipText,
          ),
        ],
      ),
    );
  }

  Widget _actionButtons() {
    final actions = <Widget>[];
    if (onFixMistakes != null) {
      actions.add(
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onFixMistakes,
            style: ElevatedButton.styleFrom(
              backgroundColor: ExerciseThemeTokens.accent,
              foregroundColor: ExerciseThemeTokens.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  ExerciseThemeTokens.buttonRadius,
                ),
              ),
            ),
            child: const Text(
              'Fix mistakes',
              style: ExerciseThemeTokens.ctaText,
            ),
          ),
        ),
      );
    }
    if (onWeakSkillDrill != null) {
      actions.add(const SizedBox(height: 12));
      actions.add(
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: onWeakSkillDrill,
            style: OutlinedButton.styleFrom(
              foregroundColor: ExerciseThemeTokens.textPrimary,
              side: const BorderSide(color: ExerciseThemeTokens.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  ExerciseThemeTokens.buttonRadius,
                ),
              ),
            ),
            child: const Text(
              'Weak skill focus',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      );
    }
    if (onFinish != null) {
      actions.add(
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onFinish,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF58CC02),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  ExerciseThemeTokens.buttonRadius,
                ),
              ),
            ),
            child: const Text('FINISH', style: ExerciseThemeTokens.ctaText),
          ),
        ),
      );
      actions.add(const SizedBox(height: 12));
    }

    if (actions.length <= 1) {
      actions.add(
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onDrillAgain,
            style: ElevatedButton.styleFrom(
              backgroundColor: ExerciseThemeTokens.accent,
              foregroundColor: ExerciseThemeTokens.onAccent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(
                  ExerciseThemeTokens.buttonRadius,
                ),
              ),
            ),
            child: const Text(
              'Drill again',
              style: ExerciseThemeTokens.ctaText,
            ),
          ),
        ),
      );
    } else if (onDrillAgain != null) {
      actions.add(const SizedBox(height: 12));
      actions.add(
        SizedBox(
          width: double.infinity,
          height: 48,
          child: TextButton(
            onPressed: onDrillAgain,
            child: const Text('Restart session'),
          ),
        ),
      );
    }
    return Column(children: actions);
  }

  String _labelForSkill(String skill) {
    switch (skill) {
      case 'listening':
        return 'Listening';
      case 'reading':
        return 'Reading';
      case 'grammar':
        return 'Grammar';
      case 'speaking':
        return 'Speaking';
      case 'character':
        return 'Characters';
      case 'production':
        return 'Production';
      default:
        return skill.substring(0, 1).toUpperCase() + skill.substring(1);
    }
  }
}

class _StatLine {
  int correct = 0;
  int total = 0;
  int latencySum = 0;

  double get accuracy => total == 0 ? 0.0 : correct / total;

  void add(bool isCorrect, int latencyMs) {
    total += 1;
    if (isCorrect) correct += 1;
    latencySum += latencyMs;
  }
}
