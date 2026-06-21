import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/path_theme.dart';
import 'package:dragon_chinese/design_system/exercise_theme.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/screens/exam_session_screen.dart';
import 'package:dragon_chinese/features/course/services/exam_scheduler.dart';
import 'package:dragon_chinese/features/course/services/local_mastery_tracker.dart';

class ExamAttempt {
  final PilotExerciseItem item;
  final bool isCorrect;
  final int latencyMs;
  final bool timedOverrun;
  final bool skipped;
  final String? skippedReason;

  ExamAttempt({
    required this.item,
    required this.isCorrect,
    required this.latencyMs,
    required this.timedOverrun,
    this.skipped = false,
    this.skippedReason,
  });
}

class ExamReportScreen extends StatelessWidget {
  final List<ExamAttempt> attempts;
  final Duration sessionDuration;
  final PilotExercisePack? packOverride;
  final String seed;
  final MasterySnapshot? masterySnapshot;

  const ExamReportScreen({
    super.key,
    required this.attempts,
    required this.sessionDuration,
    required this.seed,
    this.packOverride,
    this.masterySnapshot,
  });

  static const Map<String, double> _skillWeights = {
    'vocab': 0.4,
    'listening': 0.25,
    'reading': 0.25,
    'grammar': 0.1,
  };

  @override
  Widget build(BuildContext context) {
    final skillStats = _buildSkillStats();
    final levelStats = _buildLevelStats();
    final readiness = _computeReadinessScore(skillStats);
    final weakestSkill = _findWeakestSkill(skillStats);
    final mastery = masterySnapshot;
    final masteryScore = mastery == null
        ? null
        : mastery.overallScore(_skillWeights).round();
    final weakestLocal = mastery?.weakestSkill();
    final recommended = weakestLocal ?? weakestSkill;

    return Scaffold(
      backgroundColor: PathThemeTokens.background,
      appBar: AppBar(
        title: const Text('Exam Report'),
        backgroundColor: PathThemeTokens.surface,
        foregroundColor: PathThemeTokens.textPrimary,
        elevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _scoreCard(readiness),
          if (masteryScore != null) ...[
            const SizedBox(height: 12),
            _metricCard(
              title: 'Measured proficiency',
              value: '$masteryScore',
              subtitle: 'Based on recent practice history',
            ),
          ],
          const SizedBox(height: 16),
          _sectionTitle('Skill breakdown'),
          const SizedBox(height: 8),
          ...skillStats.entries.map((entry) => _statRow(
                entry.key,
                entry.value.correct,
                entry.value.total,
                entry.value.avgLatencyMs,
                entry.value.recommendation,
              )),
          const SizedBox(height: 16),
          _sectionTitle('Level breakdown'),
          const SizedBox(height: 8),
          ...levelStats.entries.map((entry) => _levelRow(
                entry.key,
                entry.value.correct,
                entry.value.total,
                entry.value.avgLatencyMs,
              )),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: recommended == null
                ? null
                : () => _startTargetedSession(context, recommended),
            style: ElevatedButton.styleFrom(
              backgroundColor: PathThemeTokens.brandAccent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              recommended == null
                  ? 'Next best drill'
                  : 'Next best drill: ${_labelForSkill(recommended)}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
          _supportNote(
            'Exam readiness score is a deterministic proxy, not an official HSK score.',
          ),
          if (mastery != null) ...[
            const SizedBox(height: 6),
            _supportNote('Your proficiency score updates with every attempt.'),
          ],
          if (attempts.any((a) => a.skipped)) ...[
            const SizedBox(height: 16),
            _sectionTitle('Skipped items'),
            const SizedBox(height: 8),
            _skippedSummary(),
          ],
          const SizedBox(height: 16),
          _sectionTitle('Mistakes to revisit'),
          const SizedBox(height: 8),
          _mistakeList(),
        ],
      ),
    );
  }

  Map<String, _StatLine> _buildSkillStats() {
    final map = <String, _StatLine>{};
    for (final attempt in attempts) {
      if (attempt.skipped) continue;
      final skill = attempt.item.skill;
      map.putIfAbsent(skill, () => _StatLine());
      map[skill]!.add(attempt.isCorrect, attempt.latencyMs);
    }
    for (final entry in map.entries) {
      entry.value.recommendation = _recommendationFor(entry.key, entry.value.accuracy);
    }
    return map;
  }

  Map<int, _StatLine> _buildLevelStats() {
    final map = <int, _StatLine>{};
    for (final attempt in attempts) {
      if (attempt.skipped) continue;
      final level = attempt.item.level;
      map.putIfAbsent(level, () => _StatLine());
      map[level]!.add(attempt.isCorrect, attempt.latencyMs);
    }
    return map;
  }

  int _computeReadinessScore(Map<String, _StatLine> skillStats) {
    double weighted = 0;
    double totalWeight = 0;
    for (final entry in _skillWeights.entries) {
      final stat = skillStats[entry.key];
      final acc = stat?.accuracy ?? 0.0;
      weighted += acc * entry.value;
      totalWeight += entry.value;
    }
    final baseScore = totalWeight == 0 ? 0 : (weighted / totalWeight) * 100;
    final overrunPenalty = attempts
        .where((a) => !a.skipped && a.item.level == 3 && a.timedOverrun)
        .length *
        2;
    final score = (baseScore - overrunPenalty).clamp(0, 100);
    return score.round();
  }

  String? _findWeakestSkill(Map<String, _StatLine> stats) {
    if (stats.isEmpty) return null;
    String? weakest;
    double lowest = 2.0;
    stats.forEach((skill, stat) {
      if (stat.accuracy < lowest) {
        lowest = stat.accuracy;
        weakest = skill;
      }
    });
    return weakest;
  }

  Widget _scoreCard(int readiness) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: PathThemeTokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PathThemeTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Exam readiness score', style: PathThemeTokens.sectionLabel),
          const SizedBox(height: 8),
          Text(
            '$readiness',
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Based on accuracy and timed performance',
            style: PathThemeTokens.subtitle,
          ),
        ],
      ),
    );
  }

  Widget _metricCard({
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ExerciseThemeTokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ExerciseThemeTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: ExerciseThemeTokens.caption),
          const SizedBox(height: 6),
          Text(value, style: ExerciseThemeTokens.promptTitle.copyWith(fontSize: 32)),
          const SizedBox(height: 4),
          Text(subtitle, style: ExerciseThemeTokens.promptBody),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text, style: PathThemeTokens.title);
  }

  Widget _statRow(
    String skill,
    int correct,
    int total,
    double avgLatency,
    String recommendation,
  ) {
    final accuracy = total == 0 ? 0 : (correct / total * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: PathThemeTokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PathThemeTokens.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(_labelForSkill(skill), style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          _skillPill('$accuracy%'),
          const SizedBox(width: 12),
          Text('${avgLatency.round()}ms'),
          const SizedBox(width: 12),
          Text(recommendation, style: PathThemeTokens.subtitle),
        ],
      ),
    );
  }

  Widget _levelRow(int level, int correct, int total, double avgLatency) {
    final accuracy = total == 0 ? 0 : (correct / total * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: PathThemeTokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PathThemeTokens.border),
      ),
      child: Row(
        children: [
          Expanded(child: Text('L$level', style: const TextStyle(fontWeight: FontWeight.w600))),
          _skillPill('$accuracy%'),
          const SizedBox(width: 12),
          Text('${avgLatency.round()}ms'),
        ],
      ),
    );
  }

  Widget _skillPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: ExerciseThemeTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(ExerciseThemeTokens.pillRadius),
        border: Border.all(color: ExerciseThemeTokens.border),
      ),
      child: Text(label, style: ExerciseThemeTokens.caption),
    );
  }

  String _labelForSkill(String skill) {
    switch (skill) {
      case 'listening':
        return 'Listening';
      case 'reading':
        return 'Reading';
      case 'grammar':
        return 'Grammar';
      default:
        return 'Vocab';
    }
  }

  String _recommendationFor(String skill, double accuracy) {
    if (accuracy >= 0.9) return 'Strong';
    if (accuracy >= 0.75) return 'Keep steady';
    return 'Needs focus';
  }

  Widget _supportNote(String text) {
    return Text(text, style: PathThemeTokens.subtitle);
  }

  Widget _skippedSummary() {
    final skipped = attempts.where((a) => a.skipped).toList();
    if (skipped.isEmpty) {
      return Text('No skipped items.', style: PathThemeTokens.subtitle);
    }
    final grouped = <String, int>{};
    for (final attempt in skipped) {
      final reason = attempt.skippedReason ?? 'unknown';
      grouped[reason] = (grouped[reason] ?? 0) + 1;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: grouped.entries
          .map((e) => Text('${e.key}: ${e.value}', style: PathThemeTokens.subtitle))
          .toList(),
    );
  }

  Widget _mistakeList() {
    final mistakes = attempts.where((a) => !a.skipped && !a.isCorrect).toList();
    if (mistakes.isEmpty) {
      return Text('No mistakes recorded in this session.', style: PathThemeTokens.subtitle);
    }
    final items = mistakes.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final attempt in items)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: ExerciseThemeTokens.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ExerciseThemeTokens.border),
            ),
            child: Text(
              '${attempt.item.exerciseType} • concept ${attempt.item.conceptId}',
              style: ExerciseThemeTokens.promptBody,
            ),
          ),
      ],
    );
  }

  void _startTargetedSession(BuildContext context, String skill) {
    final weights = {
      'vocab': 10,
      'listening': 10,
      'reading': 10,
      'grammar': 10,
    };
    weights[skill] = 70;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExamSessionScreen(
          seed: seed,
          packOverride: packOverride,
          configOverride: ExamSchedulerConfig(
            duration: const Duration(minutes: 8),
            totalCount: 16,
            skillWeights: weights,
            levelWeights: const {1: 50, 2: 35, 3: 15},
          ),
        ),
      ),
    );
  }
}

class _StatLine {
  int correct = 0;
  int total = 0;
  double avgLatencyMs = 0;
  String recommendation = '';

  double get accuracy => total == 0 ? 0 : correct / total;

  void add(bool isCorrect, int latencyMs) {
    total += 1;
    if (isCorrect) correct += 1;
    avgLatencyMs = total == 1
        ? latencyMs.toDouble()
        : (avgLatencyMs * 0.8) + (latencyMs * 0.2);
  }
}
