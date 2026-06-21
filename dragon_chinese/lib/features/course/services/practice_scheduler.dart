import 'dart:math';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/services/practice_models.dart';
import 'package:dragon_chinese/features/course/services/goal_profile.dart';
import 'package:dragon_chinese/features/course/services/practice_state_store.dart';

class PracticeSessionBuilder {
  PracticeSessionPlan buildPlan({
    required PilotExercisePack pack,
    required PracticeStateStore state,
    required String seed,
    required String dateBucket,
    GoalProfile? goalProfile,
    PracticeSchedulerConfig config = const PracticeSchedulerConfig(),
  }) {
    final profile = goalProfile ?? GoalProfiles.defaultProfile;
    final constraints = goalProfile == null
        ? const GoalConstraints(
            writingEnabled: true,
            maxReadingMicroPerSession: 999,
            minSpeakingPerSession: 0,
            maxNewWordsPerSession: 999,
          )
        : profile.constraints;
    final typeWeights =
        goalProfile == null ? const <String, double>{} : profile.exerciseTypeWeights;
    final now = _bucketToEpoch(dateBucket);
    final useConfigWeights =
        config.overrideGoalWeights ||
        (goalProfile == null && config.skillWeights.isNotEmpty);
    final skillCounts = _allocateSkillCounts(
      config.totalCount,
      useConfigWeights
          ? _weightsFromInts(config.skillWeights)
          : profile.skillWeights,
    );
    _applyGoalConstraints(skillCounts, constraints);
    final items = <PracticeSessionItem>[];
    final perWordCount = <int, int>{};
    String? lastType = state.lastExerciseType;
    final lastWasIncorrect = state.lastWasIncorrect;
    final limits = _SelectionLimits();

    for (final entry in skillCounts.entries) {
      final skill = entry.key;
      final count = entry.value;
      final selected = _selectForSkill(
        pack: pack,
        state: state,
        skill: skill,
        count: count,
        profile: profile,
        constraints: constraints,
        typeWeights: typeWeights,
        seed: seed,
        dateBucket: dateBucket,
        now: now,
        perWordCount: perWordCount,
        lastType: lastType,
        allowRepeat: lastWasIncorrect,
        limits: limits,
      );
      for (final item in selected) {
        items.add(item);
        lastType = item.exerciseType;
      }
    }

    final sections = _buildSections(items);
    return PracticeSessionPlan(
      seed: seed,
      dateBucket: dateBucket,
      sections: sections,
      items: items,
    );
  }

  List<PracticeSessionSection> _buildSections(List<PracticeSessionItem> items) {
    final map = <String, List<PracticeSessionItem>>{
      'Vocab': [],
      'Listening': [],
      'Reading': [],
      'Speaking': [],
    };
    for (final item in items) {
      map[_sectionForSkill(item.skill)]?.add(item);
    }
    return map.entries
        .where((e) => e.value.isNotEmpty)
        .map((e) => PracticeSessionSection(label: e.key, items: e.value))
        .toList();
  }

  String _sectionForSkill(String skill) {
    switch (skill) {
      case 'listening':
        return 'Listening';
      case 'reading':
        return 'Reading';
      case 'production':
        return 'Speaking';
      default:
        return 'Vocab';
    }
  }

  List<PracticeSessionItem> _selectForSkill({
    required PilotExercisePack pack,
    required PracticeStateStore state,
    required String skill,
    required int count,
    required GoalProfile profile,
    required GoalConstraints constraints,
    required Map<String, double> typeWeights,
    required String seed,
    required String dateBucket,
    required int now,
    required Map<int, int> perWordCount,
    required String? lastType,
    required bool allowRepeat,
    required _SelectionLimits limits,
  }) {
    if (count <= 0) return [];
    final allowedTypes = _exerciseTypesForSkill(skill, constraints);
    final preferredType = _preferredTypeForSkill(
      skill,
      state.skillTrendFor(skill),
      allowedTypes,
      profile,
      typeWeights,
    );
    final targetLevel = _targetLevelForSkill(skill, state.skillTrendFor(skill));
    var lastTypeLocal = lastType;

    final candidates = pack.items
        .where((item) => allowedTypes.contains(item.exerciseType))
        .toList();
    if (candidates.isEmpty) return [];

    final scored = candidates.map((item) {
      final skillState = state.skillStateFor(item.conceptId, skill);
      final score = _scoreItem(
        skillState: skillState,
        now: now,
        isNew: skillState.lastSeen == 0,
        preferredType: item.exerciseType == preferredType,
        level: item.level,
        targetLevel: targetLevel,
        typeWeight: typeWeights[item.exerciseType] ?? 0.0,
      );
      final stable = _stableHash('$seed|$dateBucket|${item.id}');
      return _Scored(item: item, score: score, stable: stable);
    }).toList();

    scored.sort((a, b) {
      final diff = b.score.compareTo(a.score);
      if (diff != 0) return diff;
      return a.stable.compareTo(b.stable);
    });

    final selected = <PracticeSessionItem>[];
    final perSkillSeen = <int>{};
    for (final scoredItem in scored) {
      if (selected.length >= count) break;
      final item = scoredItem.item;
      final wordId = item.conceptId;
      final countForWord = perWordCount[wordId] ?? 0;
      if (countForWord >= 2) continue;
      if (lastTypeLocal != null &&
          lastTypeLocal == item.exerciseType &&
          !allowRepeat) {
        continue;
      }
      if (_isReadingMicro(item.exerciseType) &&
          limits.readingMicroCount >= constraints.maxReadingMicroPerSession) {
        continue;
      }
      final skillState = state.skillStateFor(wordId, skill);
      final isNew = skillState.lastSeen == 0;
      if (isNew &&
          constraints.maxNewWordsPerSession > 0 &&
          limits.newWordCount >= constraints.maxNewWordsPerSession) {
        continue;
      }
      if (perSkillSeen.contains(item.conceptId) &&
          selected.length < count - 2) {
        continue;
      }
      final why = _whyFor(
        item,
        skill,
        state.skillStateFor(wordId, skill),
        now,
        profile,
        limits,
        constraints,
      );
      final reasonCodes = _reasonCodesFor(
        state.skillStateFor(wordId, skill),
        now,
      );
      final dueIn =
          skillState.dueAt > 0 ? (skillState.dueAt - now) : null;
      selected.add(
        PracticeSessionItem(
          id: item.id,
          wordId: wordId,
          exerciseType: item.exerciseType,
          skill: skill,
          level: item.level,
          why: why,
          reasonCodes: reasonCodes,
          meta: {
            'unit_id': item.unitId,
            'skill_target': skill,
            'word_stage': _stageFor(skillState.strength),
            'due_in_ms': dueIn,
          },
        ),
      );
      perWordCount[wordId] = countForWord + 1;
      perSkillSeen.add(wordId);
      lastTypeLocal = item.exerciseType;
      if (_isReadingMicro(item.exerciseType)) {
        limits.readingMicroCount += 1;
      }
      if (_isSpeakingSkill(skill)) limits.speakingCount += 1;
      if (isNew) {
        limits.newWordCount += 1;
      }
    }
    return selected;
  }

  List<String> _exerciseTypesForSkill(
    String skill,
    GoalConstraints constraints,
  ) {
    final writingEnabled = constraints.writingEnabled;
    switch (skill) {
      case 'meaning':
        return ['meaning_select', 'meaning_match'];
      case 'characters':
        return writingEnabled
            ? ['character_select', 'order_sentence']
            : ['character_select'];
      case 'pinyin':
        return ['pinyin_select', 'dictation_select'];
      case 'listening':
        return ['audio_select'];
      case 'reading':
        return ['cloze_select', 'reading_micro'];
      case 'production':
        return writingEnabled
            ? ['speak_prompted_reply', 'reply_select', 'speak_read_aloud']
            : ['speak_prompted_reply', 'speak_read_aloud'];
      default:
        return ['meaning_select'];
    }
  }

  String _preferredTypeForSkill(
    String skill,
    SkillTrend trend,
    List<String> types,
    GoalProfile profile,
    Map<String, double> typeWeights,
  ) {
    if (types.isEmpty) return '';
    if (trend.consecutiveIncorrect >= 2) {
      return types.first;
    }
    if (trend.consecutiveCorrectFast >= 3) {
      return types.last;
    }
    var best = types.first;
    var bestWeight = -1.0;
    for (final type in types) {
      final weight = typeWeights[type] ?? 0.0;
      if (weight > bestWeight) {
        bestWeight = weight;
        best = type;
      }
    }
    return best;
  }

  int _targetLevelForSkill(String skill, SkillTrend trend) {
    if (trend.consecutiveIncorrect >= 2) return 1;
    if (trend.consecutiveCorrectFast >= 3) return 3;
    return 2;
  }

  double _scoreItem({
    required SkillState skillState,
    required int now,
    required bool isNew,
    required bool preferredType,
    required int level,
    required int targetLevel,
    required double typeWeight,
  }) {
    final overdue = skillState.dueAt > 0 && skillState.dueAt <= now;
    final overdueScore = overdue
        ? 1.5 + min(1.5, (now - skillState.dueAt) / (24 * 3600 * 1000))
        : 0.0;
    final weakScore = (1.0 - skillState.strength) * 1.4;
    final novelty = isNew ? 0.6 : 0.0;
    final repetitionPenalty =
        skillState.lastSeen > 0 && now - skillState.lastSeen < 6 * 3600 * 1000
            ? 0.35
            : 0.0;
    final typeBonus = preferredType ? 0.4 : 0.0;
    final levelDelta = (3 - (level - targetLevel).abs()) * 0.05;
    final goalBias = typeWeight * 0.35;
    return overdueScore +
        weakScore +
        novelty +
        typeBonus +
        levelDelta +
        goalBias -
        repetitionPenalty;
  }

  String _whyFor(
    PilotExerciseItem item,
    String skill,
    SkillState state,
    int now,
    GoalProfile profile,
    _SelectionLimits limits,
    GoalConstraints constraints,
  ) {
    if (state.dueAt > 0 && state.dueAt <= now) {
      return _whyWithGoal('Due for review', profile, constraints);
    }
    if (state.lastSeen == 0) {
      return _whyWithGoal('New concept', profile, constraints);
    }
    if (state.strength < 0.45) {
      return _whyWithGoal('Weak skill focus', profile, constraints);
    }
    if (_isSpeakingSkill(skill)) {
      return limits.speakingCount < constraints.minSpeakingPerSession
          ? _whyWithGoal('Goal balance: speaking minimum', profile, constraints)
          : _whyWithGoal('Speaking variety', profile, constraints);
    }
    return _whyWithGoal('Variety in practice', profile, constraints);
  }

  List<String> _reasonCodesFor(SkillState state, int now) {
    if (state.dueAt > 0 && state.dueAt <= now) {
      return ['DUE_REVIEW'];
    }
    if (state.lastSeen == 0) {
      return ['NEW_WORD'];
    }
    if (state.strength < 0.45) {
      return ['WEAK_SKILL'];
    }
    return ['VARIETY'];
  }

  String _stageFor(double strength) {
    if (strength < 0.35) return 'new';
    if (strength < 0.6) return 'learning';
    if (strength < 0.82) return 'solid';
    return 'mastered';
  }

  Map<String, int> _allocateSkillCounts(
    int total,
    Map<String, double> weights,
  ) {
    if (total <= 0 || weights.isEmpty) return {};
    final keys = weights.keys.toList()..sort();
    final raw = <String, double>{};
    for (final key in keys) {
      raw[key] = total * (weights[key] ?? 0.0);
    }
    final base = <String, int>{};
    for (final key in keys) {
      base[key] = raw[key]!.floor();
    }
    var assigned = base.values.fold<int>(0, (sum, v) => sum + v);
    var remainder = total - assigned;
    if (remainder > 0) {
      final fractional = keys.toList()
        ..sort((a, b) {
          final diff = (raw[b]! - raw[b]!.floor()) - (raw[a]! - raw[a]!.floor());
          if (diff.abs() > 1e-9) {
            return diff > 0 ? 1 : -1;
          }
          return a.compareTo(b);
        });
      for (final key in fractional) {
        if (remainder == 0) break;
        base[key] = (base[key] ?? 0) + 1;
        remainder -= 1;
      }
    }
    return base;
  }

  Map<String, double> _weightsFromInts(Map<String, int> weights) {
    final total = weights.values.fold<int>(0, (sum, v) => sum + v);
    if (total <= 0) return {};
    return weights.map((k, v) => MapEntry(k, v / total));
  }

  void _applyGoalConstraints(
    Map<String, int> counts,
    GoalConstraints constraints,
  ) {
    if (constraints.minSpeakingPerSession <= 0) return;
    final total = counts.values.fold<int>(0, (sum, v) => sum + v);
    if (total <= 0) return;
    final targetMin =
        constraints.minSpeakingPerSession > total
            ? total
            : constraints.minSpeakingPerSession;
    final current = counts['production'] ?? 0;
    if (current >= targetMin) return;
    var needed = targetMin - current;
    counts['production'] = targetMin;
    final candidates = counts.keys
        .where((k) => k != 'production')
        .toList()
      ..sort((a, b) {
        final diff = (counts[b] ?? 0).compareTo(counts[a] ?? 0);
        if (diff != 0) return diff;
        return a.compareTo(b);
      });
    for (final key in candidates) {
      if (needed <= 0) break;
      final available = counts[key] ?? 0;
      if (available <= 0) continue;
      final reduce = available >= needed ? needed : available;
      counts[key] = available - reduce;
      needed -= reduce;
    }
  }

  bool _isReadingMicro(String type) => type == 'reading_micro';

  bool _isSpeakingSkill(String skill) => skill == 'production' || skill == 'speaking';

  String _whyWithGoal(String base, GoalProfile profile, GoalConstraints constraints) {
    if (constraints.minSpeakingPerSession == 0 &&
        constraints.maxNewWordsPerSession >= 999 &&
        constraints.maxReadingMicroPerSession >= 999 &&
        constraints.writingEnabled) {
      return base;
    }
    return '$base · ${profile.label}';
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

  int _bucketToEpoch(String bucket) {
    try {
      final date = DateTime.parse(bucket);
      return DateTime(date.year, date.month, date.day).millisecondsSinceEpoch;
    } catch (_) {
      return DateTime.now().millisecondsSinceEpoch;
    }
  }
}

class _Scored {
  final PilotExerciseItem item;
  final double score;
  final int stable;

  _Scored({required this.item, required this.score, required this.stable});
}

class _SelectionLimits {
  int readingMicroCount = 0;
  int speakingCount = 0;
  int newWordCount = 0;
}
