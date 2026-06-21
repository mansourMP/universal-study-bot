import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dragon_chinese/features/course/services/goal_profile.dart';
import 'package:dragon_chinese/features/course/services/goal_profile_store.dart';
import 'package:dragon_chinese/features/course/services/context_template_resolver.dart';
import 'package:dragon_chinese/features/course/services/practice_scheduler.dart';
import 'package:dragon_chinese/features/course/services/practice_state_store.dart';
import 'package:dragon_chinese/features/course/services/practice_models.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';

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
        id: 'character_select_2',
        exerciseType: 'character_select',
        conceptId: 2,
        unitId: '1',
        level: 1,
        skill: 'vocab',
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
      PilotExerciseItem(
        id: 'pinyin_select_3',
        exerciseType: 'pinyin_select',
        conceptId: 3,
        unitId: '1',
        level: 1,
        skill: 'vocab',
        constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
        prompt: const PilotPrompt(hanzi: '吗', pinyin: 'ma', meaning: 'question'),
        choices: const ['ma', 'ba', 'na', 'la'],
        answerIndex: 0,
        options: const [],
        correctOptionId: null,
        meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
        why: PilotWhy(reasons: const ['test'], signals: PilotWhySignals()),
        payload: const {},
        questions: const [],
      ),
      PilotExerciseItem(
        id: 'audio_select_4',
        exerciseType: 'audio_select',
        conceptId: 4,
        unitId: '1',
        level: 1,
        skill: 'listening',
        constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
        prompt: const PilotPrompt(hanzi: '谢谢', pinyin: 'xie xie', meaning: 'thanks'),
        choices: const ['谢谢', '你好', '再见', '没关系'],
        answerIndex: 0,
        options: const [],
        correctOptionId: null,
        meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
        why: PilotWhy(reasons: const ['test'], signals: PilotWhySignals()),
        payload: const {},
        questions: const [],
      ),
      PilotExerciseItem(
        id: 'cloze_select_5',
        exerciseType: 'cloze_select',
        conceptId: 5,
        unitId: '1',
        level: 1,
        skill: 'reading',
        constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
        prompt: const PilotPrompt(hanzi: '是', pinyin: 'shi', meaning: 'to be'),
        choices: const ['是', '有', '在', '去'],
        answerIndex: 0,
        options: const [],
        correctOptionId: null,
        meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
        why: PilotWhy(reasons: const ['test'], signals: PilotWhySignals()),
        payload: const {'sentence': '我是 ___ 老师。'},
        questions: const [],
      ),
      PilotExerciseItem(
        id: 'reading_micro_6',
        exerciseType: 'reading_micro',
        conceptId: 6,
        unitId: '1',
        level: 1,
        skill: 'reading',
        constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
        prompt: const PilotPrompt(hanzi: '喝', pinyin: 'he', meaning: 'drink'),
        choices: const [],
        answerIndex: 0,
        options: const [],
        correctOptionId: null,
        meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
        why: PilotWhy(reasons: const ['test'], signals: PilotWhySignals()),
        payload: const {},
        reading: PilotReading(
          titleZh: '小对话',
          titleEn: 'Short dialogue',
          storyZh: '我喝水。',
          storyPinyin: 'wo he shui',
          storyEn: 'I drink water.',
        ),
        questions: [
          PilotQuestion(
            type: 'meaning_select',
            prompt: const {'text': 'What do they drink?'},
            choices: ['water', 'tea', 'coffee', 'milk'],
            answerIndex: 0,
          ),
        ],
      ),
      PilotExerciseItem(
        id: 'reply_select_7',
        exerciseType: 'reply_select',
        conceptId: 7,
        unitId: '1',
        level: 1,
        skill: 'production',
        constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
        prompt: const PilotPrompt(hanzi: '请问', pinyin: 'qing wen', meaning: 'excuse me'),
        choices: const ['你好', '谢谢', '再见', '不客气'],
        answerIndex: 0,
        options: const [],
        correctOptionId: null,
        meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
        why: PilotWhy(reasons: const ['test'], signals: PilotWhySignals()),
        payload: const {},
        questions: const [],
      ),
      PilotExerciseItem(
        id: 'speak_prompted_reply_8',
        exerciseType: 'speak_prompted_reply',
        conceptId: 8,
        unitId: '1',
        level: 1,
        skill: 'production',
        constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
        promptText: 'Respond politely.',
        prompt: const PilotPrompt(hanzi: '请', pinyin: 'qing', meaning: 'please'),
        choices: const [],
        answerIndex: 0,
        options: const [],
        correctOptionId: null,
        meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
        why: PilotWhy(reasons: const ['test'], signals: PilotWhySignals()),
        payload: const {'sample_answers': ['好的', '没问题']},
        questions: const [],
      ),
    ],
  );
}

void main() {
  test('GoalProfileStore persists selection', () async {
    SharedPreferences.setMockInitialValues({});
    await GoalProfileStore.setGoal(GoalType.exam);
    final stored = await GoalProfileStore.getGoal();
    expect(stored, GoalType.exam);
  });

  test('ContextTemplateResolver is deterministic', () {
    final resolver = ContextTemplateResolver(GoalProfiles.professional);
    final a = resolver.resolvePrompt(
      wordId: 10,
      unitId: 'u1',
      exerciseType: 'reply_select',
      index: 2,
      word: '你好',
      meaning: 'hello',
    );
    final b = resolver.resolvePrompt(
      wordId: 10,
      unitId: 'u1',
      exerciseType: 'reply_select',
      index: 2,
      word: '你好',
      meaning: 'hello',
    );
    expect(a, b);
  });

  test('GoalProfile changes skill distribution deterministically', () {
    final store = PracticeStateStore.fromData();
    final builder = PracticeSessionBuilder();
    final examPlan = builder.buildPlan(
      pack: _pack(),
      state: store,
      seed: 'seed',
      dateBucket: '2026-02-03',
      goalProfile: GoalProfiles.exam,
      config: const PracticeSchedulerConfig(totalCount: 6),
    );
    final speakPlan = builder.buildPlan(
      pack: _pack(),
      state: store,
      seed: 'seed',
      dateBucket: '2026-02-03',
      goalProfile: GoalProfiles.speaking,
      config: const PracticeSchedulerConfig(totalCount: 6),
    );
    final examSpeaking = examPlan.items.where((e) => e.skill == 'production').length;
    final speakSpeaking =
        speakPlan.items.where((e) => e.skill == 'production').length;
    expect(speakSpeaking, greaterThanOrEqualTo(examSpeaking));
    expect(speakSpeaking, greaterThanOrEqualTo(1));
  });

  test('GoalProfile writing constraint removes writing-heavy types', () {
    const customProfile = GoalProfile(
      goal: GoalType.speaking,
      label: 'Speaking Focus',
      skillWeights: {
        'meaning': 0.2,
        'characters': 0.6,
        'pinyin': 0.1,
        'listening': 0.05,
        'reading': 0.03,
        'production': 0.02,
      },
      exerciseTypeWeights: {
        'character_select': 0.6,
        'order_sentence': 0.4,
      },
      contextTemplates: ['Use {word} in a reply.'],
      constraints: GoalConstraints(
        writingEnabled: false,
        maxReadingMicroPerSession: 2,
        minSpeakingPerSession: 0,
        maxNewWordsPerSession: 6,
      ),
    );
    final pack = PilotExercisePack(
      schemaVersion: 3,
      generatedAt: '2026-02-03',
      items: [
        PilotExerciseItem(
          id: 'character_select',
          exerciseType: 'character_select',
          conceptId: 1,
          unitId: '1',
          level: 1,
          skill: 'vocab',
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
        PilotExerciseItem(
          id: 'order_sentence',
          exerciseType: 'order_sentence',
          conceptId: 2,
          unitId: '1',
          level: 1,
          skill: 'vocab',
          constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
          prompt: const PilotPrompt(hanzi: '我', pinyin: 'wo', meaning: 'I'),
          choices: const [],
          answerIndex: 0,
          options: const [],
          correctOptionId: null,
          meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
          why: PilotWhy(reasons: const ['test'], signals: PilotWhySignals()),
          payload: const {'chunks': ['我', '是', '学生'], 'answer': ['我', '是', '学生']},
          questions: const [],
        ),
      ],
    );
    final store = PracticeStateStore.fromData();
    final builder = PracticeSessionBuilder();
    final plan = builder.buildPlan(
      pack: pack,
      state: store,
      seed: 'seed',
      dateBucket: '2026-02-03',
      goalProfile: customProfile,
      config: const PracticeSchedulerConfig(
        totalCount: 1,
        skillWeights: {'characters': 100},
        overrideGoalWeights: true,
      ),
    );
    expect(plan.items.first.exerciseType, 'character_select');
  });
}
