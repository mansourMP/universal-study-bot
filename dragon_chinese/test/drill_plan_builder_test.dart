import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/services/drill_plan_builder.dart';
import 'package:dragon_chinese/features/course/services/mastery_store.dart';
import 'package:dragon_chinese/features/course/services/mastery_models.dart';

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
        choices: const ['you', 'me', 'he', 'she'],
        answerIndex: 0,
        options: const [],
        correctOptionId: null,
        meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
        why: PilotWhy(reasons: const ['test'], signals: PilotWhySignals()),
        payload: const {},
        questions: const [],
      ),
      PilotExerciseItem(
        id: 'audio_select_2',
        exerciseType: 'audio_select',
        conceptId: 2,
        unitId: '1',
        level: 1,
        skill: 'listening',
        constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
        prompt: const PilotPrompt(hanzi: '好', pinyin: 'hao', meaning: 'good'),
        choices: const ['好', '坏', '行', '去'],
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
  test('DrillPlanBuilder prioritizes due review', () {
    final mastery = MasteryStore.fromData(entries: {
      1: WordSkillMastery(
        wordId: 1,
        skills: {
          'meaning': SkillMasteryState.initial().copyWith(
            score: 0.2,
            dueAt: 1,
            lastSeenAt: 1,
          ),
        },
      ),
      2: WordSkillMastery(
        wordId: 2,
        skills: {
          'listening': SkillMasteryState.initial().copyWith(
            score: 0.4,
            dueAt: 9999999999,
            lastSeenAt: 1,
          ),
        },
      ),
    });

    final builder = DrillPlanBuilder();
    final plan = builder.buildPlan(
      pack: _pack(),
      mastery: mastery,
      seed: 'seed',
      dateBucket: '2026-02-03',
      config: const DrillPlanConfig(totalCount: 1, dueCount: 1, weakCount: 0, newCount: 0),
    );
    expect(plan.items.first.wordId, 1);
    expect(plan.items.first.reasonCodes.contains('DUE_REVIEW'), true);
  });
}
