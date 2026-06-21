import 'dart:math';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/services/mastery_store.dart';
import 'package:dragon_chinese/features/course/services/mastery_models.dart';
import 'package:dragon_chinese/features/course/services/practice_models.dart';

class DrillPlanConfig {
  final int totalCount;
  final int dueCount;
  final int weakCount;
  final int newCount;

  const DrillPlanConfig({
    this.totalCount = 16,
    this.dueCount = 6,
    this.weakCount = 6,
    this.newCount = 4,
  });
}

class DrillPlanBuilder {
  PracticeSessionPlan buildPlan({
    required PilotExercisePack pack,
    required MasteryStore mastery,
    required String seed,
    required String dateBucket,
    DrillPlanConfig config = const DrillPlanConfig(),
    String? lastExerciseType,
    bool lastWasIncorrect = false,
  }) {
    final now = _bucketToEpoch(dateBucket);
    final items = <PracticeSessionItem>[];
    final perWordCount = <int, int>{};

    final dueItems = _selectItems(
      pack: pack,
      mastery: mastery,
      seed: seed,
      dateBucket: dateBucket,
      now: now,
      count: config.dueCount,
      perWordCount: perWordCount,
      lastType: lastExerciseType,
      allowRepeat: lastWasIncorrect,
      reasonCode: 'DUE_REVIEW',
      includeNew: false,
      preferAudio: true,
    );
    items.addAll(dueItems);
    lastExerciseType = items.isEmpty ? lastExerciseType : items.last.exerciseType;

    final weakItems = _selectItems(
      pack: pack,
      mastery: mastery,
      seed: seed,
      dateBucket: dateBucket,
      now: now,
      count: config.weakCount,
      perWordCount: perWordCount,
      lastType: lastExerciseType,
      allowRepeat: lastWasIncorrect,
      reasonCode: 'WEAK_SKILL',
      includeNew: false,
      preferAudio: true,
    );
    items.addAll(weakItems);
    lastExerciseType = items.isEmpty ? lastExerciseType : items.last.exerciseType;

    final newItems = _selectItems(
      pack: pack,
      mastery: mastery,
      seed: seed,
      dateBucket: dateBucket,
      now: now,
      count: config.newCount,
      perWordCount: perWordCount,
      lastType: lastExerciseType,
      allowRepeat: lastWasIncorrect,
      reasonCode: 'NEW_WORD_CAP',
      includeNew: true,
      preferAudio: false,
    );
    items.addAll(newItems);

    final trimmed = items.take(config.totalCount).toList();
    final sections = _buildSections(trimmed);
    return PracticeSessionPlan(
      seed: seed,
      dateBucket: dateBucket,
      sections: sections,
      items: trimmed,
    );
  }

  List<PracticeSessionItem> _selectItems({
    required PilotExercisePack pack,
    required MasteryStore mastery,
    required String seed,
    required String dateBucket,
    required int now,
    required int count,
    required Map<int, int> perWordCount,
    required String? lastType,
    required bool allowRepeat,
    required String reasonCode,
    required bool includeNew,
    required bool preferAudio,
  }) {
    if (count <= 0) return [];
    final candidates = pack.items.where((item) {
      final skill = _skillForType(item.exerciseType);
      if (skill == null) return false;
      final state = mastery.skillStateFor(item.conceptId, skill);
      if (!includeNew && state.lastSeenAt == 0) return false;
      return true;
    }).toList();

    final scored = candidates.map((item) {
      final skill = _skillForType(item.exerciseType) ?? 'meaning';
      final state = mastery.skillStateFor(item.conceptId, skill);
      final score = _scoreItem(state, now, includeNew);
      final audioBonus =
          (preferAudio && item.audioUrl != null && item.audioUrl!.isNotEmpty)
              ? 0.15
              : 0.0;
      final stable = _stableHash('$seed|$dateBucket|${item.id}');
      return _Scored(item: item, score: score + audioBonus, stable: stable);
    }).toList();

    scored.sort((a, b) {
      final diff = b.score.compareTo(a.score);
      if (diff != 0) return diff;
      return a.stable.compareTo(b.stable);
    });

    final selected = <PracticeSessionItem>[];
    var lastTypeLocal = lastType;
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
      final skill = _skillForType(item.exerciseType) ?? 'meaning';
      final state = mastery.skillStateFor(wordId, skill);
      selected.add(
        PracticeSessionItem(
          id: item.id,
          wordId: wordId,
          exerciseType: item.exerciseType,
          skill: skill,
          level: item.level,
          why: _whyText(reasonCode, state, now),
          reasonCodes: [reasonCode],
          meta: {
            'unit_id': item.unitId,
            'skill_target': skill,
            'word_stage': state.stage.name,
            'due_in_ms': state.dueAt > 0 ? (state.dueAt - now) : null,
          },
        ),
      );
      perWordCount[wordId] = countForWord + 1;
      lastTypeLocal = item.exerciseType;
    }
    return selected;
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

  String? _skillForType(String type) {
    switch (type) {
      case 'meaning_select':
      case 'meaning_match':
        return 'meaning';
      case 'character_select':
      case 'order_sentence':
        return 'character';
      case 'audio_select':
      case 'dictation_select':
      case 'pinyin_select':
        return 'listening';
      case 'cloze_select':
      case 'reading_micro':
        return 'reading';
      case 'reply_select':
      case 'speak_prompted_reply':
      case 'speak_read_aloud':
        return 'production';
      default:
        return null;
    }
  }

  double _scoreItem(SkillMasteryState state, int now, bool includeNew) {
    final overdue = state.dueAt > 0 && state.dueAt <= now;
    final overdueScore = overdue
        ? 1.4 + min(1.2, (now - state.dueAt) / (24 * 3600 * 1000))
        : 0.0;
    final weakScore = (1.0 - state.score) * 1.2;
    final novelty = includeNew && state.lastSeenAt == 0 ? 0.5 : 0.0;
    final repetitionPenalty =
        state.lastSeenAt > 0 && now - state.lastSeenAt < 6 * 3600 * 1000
            ? 0.35
            : 0.0;
    return overdueScore + weakScore + novelty - repetitionPenalty;
  }

  String _whyText(String code, SkillMasteryState state, int now) {
    switch (code) {
      case 'DUE_REVIEW':
        return 'Due review';
      case 'WEAK_SKILL':
        return 'Weak skill focus';
      case 'NEW_WORD_CAP':
        return 'New word cap';
      case 'MISTAKE_REVIEW':
        return 'Mistake review';
      default:
        if (state.dueAt > 0 && state.dueAt <= now) return 'Due review';
        return 'Focused drill';
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
