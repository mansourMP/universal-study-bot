import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/services/exam_scheduler.dart';
import 'package:dragon_chinese/features/course/services/mistake_stats.dart';
import 'package:dragon_chinese/features/course/services/performance_models.dart';

PilotExercisePack _makePack() {
  return PilotExercisePack(
    schemaVersion: 3,
    generatedAt: '2026-02-02',
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
        why: PilotWhy(reasons: const ['deterministic'], signals: PilotWhySignals()),
        payload: const {},
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
        prompt: const PilotPrompt(hanzi: '我', pinyin: 'wo', meaning: 'I'),
        choices: const ['我', '你', '他', '她'],
        answerIndex: 0,
        options: const [],
        correctOptionId: null,
        meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
        why: PilotWhy(reasons: const ['deterministic'], signals: PilotWhySignals()),
        payload: const {},
        questions: const [],
      ),
      PilotExerciseItem(
        id: 'audio_select_3',
        exerciseType: 'audio_select',
        conceptId: 3,
        unitId: '1',
        level: 1,
        skill: 'listening',
        constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
        prompt: const PilotPrompt(hanzi: '他', pinyin: 'ta', meaning: 'he'),
        choices: const ['他', '她', '你', '我'],
        answerIndex: 0,
        options: const [],
        correctOptionId: null,
        meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
        why: PilotWhy(reasons: const ['deterministic'], signals: PilotWhySignals()),
        payload: const {},
        questions: const [],
      ),
      PilotExerciseItem(
        id: 'reading_micro_4',
        exerciseType: 'reading_micro',
        conceptId: 4,
        unitId: '1',
        level: 1,
        skill: 'reading',
        constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
        prompt: const PilotPrompt(hanzi: '测试', pinyin: 'ceshi', meaning: 'test'),
        choices: const [],
        answerIndex: 0,
        options: const [],
        correctOptionId: null,
        meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
        why: PilotWhy(reasons: const ['deterministic'], signals: PilotWhySignals()),
        reading: PilotReading(
          titleZh: '测试',
          titleEn: 'Test',
          storyZh: '这是一个故事。',
          storyPinyin: '',
          storyEn: 'This is a story.',
        ),
        payload: const {},
        questions: [
          PilotQuestion(
            type: 'meaning_select',
            prompt: {'hanzi': '你'},
            choices: ['you', 'me'],
            answerIndex: 0,
          ),
          PilotQuestion(
            type: 'detail_select',
            prompt: {'question': 'Which detail appears?'},
            choices: ['This is a story.', 'Another line.'],
            answerIndex: 0,
          ),
        ],
      ),
    ],
  );
}

void main() {
  test('ExamScheduler is deterministic for same seed', () {
    final pack = _makePack();
    final scheduler = ExamScheduler();
    final mistakes = MistakeStats(typeWrongCount: const {});
    final performance = PerformanceSnapshot({});
    final planA = scheduler.buildPlan(
      pack: pack,
      seed: 'seed-1',
      performance: performance,
      mistakes: mistakes,
      config: const ExamSchedulerConfig(
        duration: Duration(minutes: 10),
        totalCount: 4,
        skillWeights: {'vocab': 50, 'listening': 25, 'reading': 25},
        levelWeights: {1: 100, 2: 0, 3: 0},
      ),
    );
    final planB = scheduler.buildPlan(
      pack: pack,
      seed: 'seed-1',
      performance: performance,
      mistakes: mistakes,
      config: const ExamSchedulerConfig(
        duration: Duration(minutes: 10),
        totalCount: 4,
        skillWeights: {'vocab': 50, 'listening': 25, 'reading': 25},
        levelWeights: {1: 100, 2: 0, 3: 0},
      ),
    );

    final a = planA.items.map((i) => '${i.item.exerciseType}:${i.item.conceptId}').toList();
    final b = planB.items.map((i) => '${i.item.exerciseType}:${i.item.conceptId}').toList();

    expect(a, b);
  });
}
