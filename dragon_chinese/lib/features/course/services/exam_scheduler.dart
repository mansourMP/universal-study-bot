import 'dart:math';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/services/mistake_stats.dart';
import 'package:dragon_chinese/features/course/services/performance_models.dart';

class ExamSessionPlan {
  final Duration duration;
  final List<ExamSessionItem> items;
  final Map<String, int> counts;

  ExamSessionPlan({
    required this.duration,
    required this.items,
    required this.counts,
  });
}

class ExamSessionItem {
  final String section;
  final PilotExerciseItem item;

  ExamSessionItem({required this.section, required this.item});
}

class ExamSchedulerConfig {
  final Duration duration;
  final int totalCount;
  final Map<String, int> skillWeights;
  final Map<int, int> levelWeights;

  const ExamSchedulerConfig({
    required this.duration,
    this.totalCount = 30,
    this.skillWeights = const {
      'vocab': 40,
      'listening': 22,
      'reading': 22,
      'grammar': 6,
      'speaking': 10,
    },
    this.levelWeights = const {1: 50, 2: 35, 3: 15},
  });
}

class ExamScheduler {
  ExamSessionPlan buildPlan({
    required PilotExercisePack pack,
    required String seed,
    required PerformanceSnapshot performance,
    MistakeStats? mistakes,
    ExamSchedulerConfig config =
        const ExamSchedulerConfig(duration: Duration(minutes: 18)),
  }) {
    final pools = <String, List<PilotExerciseItem>>{};
    for (final item in pack.items) {
      pools.putIfAbsent(item.skill, () => []).add(item);
    }

    final skillCounts = _allocateSkillCounts(config.totalCount, config.skillWeights);
    final levelWeights = config.levelWeights;

    final items = <ExamSessionItem>[];
    skillCounts.forEach((skill, count) {
      final pool = pools[skill] ?? [];
      final levelCounts = _allocateLevelCounts(count, levelWeights);
      _adaptLevels(levelCounts, performance, skill);
      final selected = _selectByLevel(pool, levelCounts, seed, skill);
      items.addAll(selected.map(
        (item) => ExamSessionItem(
          section: _sectionLabel(skill),
          item: item,
        ),
      ));
    });

    return ExamSessionPlan(
      duration: config.duration,
      items: items,
      counts: skillCounts,
    );
  }

  List<PilotExerciseItem> _selectByLevel(
    List<PilotExerciseItem> pool,
    Map<int, int> levelCounts,
    String seed,
    String skill,
  ) {
    final selected = <PilotExerciseItem>[];
    final remaining = List<PilotExerciseItem>.from(pool);
    for (final level in [1, 2, 3]) {
      final bucket = remaining.where((i) => i.level == level).toList();
      final count = levelCounts[level] ?? 0;
      selected.addAll(_selectDeterministic(bucket, count, seed, '$skill:L$level'));
      for (final item in selected) {
        remaining.remove(item);
      }
    }
    if (selected.length < levelCounts.values.fold(0, (a, b) => a + b)) {
      final fallbackCount =
          levelCounts.values.fold(0, (a, b) => a + b) - selected.length;
      selected.addAll(_selectDeterministic(remaining, fallbackCount, seed, '$skill:fallback'));
    }
    return selected;
  }

  List<PilotExerciseItem> _selectDeterministic(
    List<PilotExerciseItem> pool,
    int count,
    String seed,
    String tag,
  ) {
    if (pool.isEmpty || count <= 0) return [];
    final scored = pool
        .map((item) => MapEntry(item, _stableHash('$seed|$tag|${item.id}')))
        .toList();
    scored.sort((a, b) => a.value.compareTo(b.value));
    return scored.take(min(count, scored.length)).map((e) => e.key).toList();
  }

  Map<String, int> _allocateSkillCounts(int total, Map<String, int> weights) {
    final counts = <String, int>{};
    int assigned = 0;
    final keys = weights.keys.toList();
    for (var i = 0; i < keys.length; i++) {
      final skill = keys[i];
      if (i == keys.length - 1) {
        counts[skill] = total - assigned;
      } else {
        final count = (total * weights[skill]! / 100).round();
        counts[skill] = count;
        assigned += count;
      }
    }
    return counts;
  }

  Map<int, int> _allocateLevelCounts(int total, Map<int, int> weights) {
    final counts = <int, int>{};
    int assigned = 0;
    final levels = weights.keys.toList()..sort();
    for (var i = 0; i < levels.length; i++) {
      final level = levels[i];
      if (i == levels.length - 1) {
        counts[level] = total - assigned;
      } else {
        final count = (total * weights[level]! / 100).round();
        counts[level] = count;
        assigned += count;
      }
    }
    return counts;
  }

  void _adaptLevels(
    Map<int, int> levelCounts,
    PerformanceSnapshot performance,
    String skill,
  ) {
    final acc1 = performance.accuracy(skill, 1);
    final lat1 = performance.latency(skill, 1);
    if (acc1 > 0.88 && lat1 > 0 && lat1 < 2500 && (levelCounts[1] ?? 0) > 0) {
      levelCounts[1] = (levelCounts[1] ?? 0) - 1;
      levelCounts[2] = (levelCounts[2] ?? 0) + 1;
    }
    final acc2 = performance.accuracy(skill, 2);
    final lat2 = performance.latency(skill, 2);
    if (acc2 > 0.88 && lat2 > 0 && lat2 < 2500 && (levelCounts[2] ?? 0) > 0) {
      levelCounts[2] = (levelCounts[2] ?? 0) - 1;
      levelCounts[3] = (levelCounts[3] ?? 0) + 1;
    }
  }

  String _sectionLabel(String skill) {
    switch (skill) {
      case 'listening':
        return 'Listening';
      case 'reading':
        return 'Reading';
      case 'grammar':
        return 'Grammar';
      case 'speaking':
        return 'Speaking';
      default:
        return 'Vocab';
    }
  }

  int _stableHash(String input) {
    const int fnvPrime = 0x01000193;
    int hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash;
  }
}
