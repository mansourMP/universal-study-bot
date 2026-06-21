import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/services/practice_scheduler.dart';
import 'package:dragon_chinese/features/course/services/practice_state_store.dart';
import 'package:dragon_chinese/features/course/services/practice_models.dart';

PilotExercisePack _pack() {
  return PilotExercisePack(
    schemaVersion: 3,
    generatedAt: '2026-02-03',
    items: [
      PilotExerciseItem(
        id: 'meaning_select_1',
        exerciseType: 'meaning_select',
        conceptId: 1,
        unitId: '1',
        level: 1,
        skill: 'vocab',
        constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
        prompt: const PilotPrompt(hanzi: '你', pinyin: 'ni', meaning: 'you'),
        choices: const ['you', 'me'],
        answerIndex: 0,
        options: const [],
        correctOptionId: null,
        meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
        why: PilotWhy(reasons: const ['test'], signals: PilotWhySignals()),
        payload: const {},
        questions: const [],
      ),
      PilotExerciseItem(
        id: 'meaning_match_1',
        exerciseType: 'meaning_match',
        conceptId: 1,
        unitId: '1',
        level: 2,
        skill: 'vocab',
        constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
        prompt: const PilotPrompt(hanzi: '你', pinyin: 'ni', meaning: 'you'),
        choices: const [],
        answerIndex: 0,
        options: const [],
        correctOptionId: null,
        meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
        why: PilotWhy(reasons: const ['test'], signals: PilotWhySignals()),
        payload: const {
          'left': ['你'],
          'right': ['you'],
          'mapping': [0],
        },
        questions: const [],
      ),
      PilotExerciseItem(
        id: 'character_select_2',
        exerciseType: 'character_select',
        conceptId: 2,
        unitId: '1',
        level: 1,
        skill: 'vocab',
        constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
        prompt: const PilotPrompt(hanzi: '好', pinyin: 'hao', meaning: 'good'),
        choices: const ['好', '坏'],
        answerIndex: 0,
        options: const [],
        correctOptionId: null,
        meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
        why: PilotWhy(reasons: const ['test'], signals: PilotWhySignals()),
        payload: const {},
        questions: const [],
      ),
    ],
  );
}

void main() {
  test('PracticeScheduler is deterministic for same seed', () {
    final store = PracticeStateStore.fromData();
    final builder = PracticeSessionBuilder();
    final plan1 = builder.buildPlan(
      pack: _pack(),
      state: store,
      seed: 'seed',
      dateBucket: '2026-02-03',
      config: const PracticeSchedulerConfig(
        totalCount: 2,
        skillWeights: {'meaning': 100},
      ),
    );
    final plan2 = builder.buildPlan(
      pack: _pack(),
      state: store,
      seed: 'seed',
      dateBucket: '2026-02-03',
      config: const PracticeSchedulerConfig(
        totalCount: 2,
        skillWeights: {'meaning': 100},
      ),
    );

    expect(plan1.items.map((e) => e.id), plan2.items.map((e) => e.id));
  });

  test('PracticeScheduler avoids consecutive duplicate types', () {
    final store = PracticeStateStore.fromData();
    final builder = PracticeSessionBuilder();
    final plan = builder.buildPlan(
      pack: _pack(),
      state: store,
      seed: 'seed',
      dateBucket: '2026-02-03',
      config: const PracticeSchedulerConfig(
        totalCount: 3,
        skillWeights: {'meaning': 100},
      ),
    );
    for (var i = 1; i < plan.items.length; i++) {
      expect(
        plan.items[i].exerciseType == plan.items[i - 1].exerciseType,
        false,
      );
    }
  });

  test('PracticeScheduler steps down/up by skill trend', () {
    final trends = {
      'meaning': const SkillTrend(
        consecutiveIncorrect: 2,
        consecutiveCorrectFast: 0,
        lastLatencyMs: 0,
      ),
    };
    final store = PracticeStateStore.fromData(skillTrends: trends);
    final builder = PracticeSessionBuilder();
    final plan = builder.buildPlan(
      pack: _pack(),
      state: store,
      seed: 'seed',
      dateBucket: '2026-02-03',
      config: const PracticeSchedulerConfig(
        totalCount: 1,
        skillWeights: {'meaning': 100},
      ),
    );
    expect(plan.items.first.exerciseType, 'meaning_select');

    final upTrends = {
      'meaning': const SkillTrend(
        consecutiveIncorrect: 0,
        consecutiveCorrectFast: 3,
        lastLatencyMs: 1200,
      ),
    };
    final storeUp = PracticeStateStore.fromData(skillTrends: upTrends);
    final planUp = builder.buildPlan(
      pack: _pack(),
      state: storeUp,
      seed: 'seed',
      dateBucket: '2026-02-03',
      config: const PracticeSchedulerConfig(
        totalCount: 1,
        skillWeights: {'meaning': 100},
      ),
    );
    expect(planUp.items.first.exerciseType, 'meaning_match');
  });

  test('PracticeScheduler outputs valid reason codes for each item', () {
    final store = PracticeStateStore.fromData();
    final builder = PracticeSessionBuilder();
    final plan = builder.buildPlan(
      pack: _pack(),
      state: store,
      seed: 'seed',
      dateBucket: '2026-02-03',
      config: const PracticeSchedulerConfig(
        totalCount: 2,
        skillWeights: {'meaning': 100},
      ),
    );

    const validCodes = {
      'DUE_REVIEW',
      'NEW_WORD',
      'WEAK_SKILL',
      'VARIETY',
      'NEW_WORD_CAP',
      'MISTAKE_REVIEW',
      'GOAL_BALANCE',
    };
    for (final item in plan.items) {
      expect(
        item.reasonCodes.isNotEmpty,
        true,
        reason: 'Item ${item.id} should have reason codes',
      );
      for (final code in item.reasonCodes) {
        expect(
          validCodes.contains(code),
          true,
          reason: 'Code $code should be valid',
        );
      }
      expect(
        item.why.isNotEmpty,
        true,
        reason: 'Item ${item.id} should have why text',
      );
    }
  });

  test('PracticeScheduler respects per-word cap of 2', () {
    final store = PracticeStateStore.fromData();
    final builder = PracticeSessionBuilder();
    final plan = builder.buildPlan(
      pack: _pack(),
      state: store,
      seed: 'seed',
      dateBucket: '2026-02-03',
      config: const PracticeSchedulerConfig(
        totalCount: 10,
        skillWeights: {'meaning': 100},
      ),
    );

    final wordCounts = <int, int>{};
    for (final item in plan.items) {
      wordCounts[item.wordId] = (wordCounts[item.wordId] ?? 0) + 1;
    }
    for (final count in wordCounts.values) {
      expect(count, lessThanOrEqualTo(2), reason: 'Per-word cap should be 2');
    }
  });
}
