import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/screens/exam_session_screen.dart';
import 'package:dragon_chinese/features/course/services/exam_scheduler.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/multiple_choice_exercise.dart';
import 'package:shared_preferences/shared_preferences.dart';

PilotExercisePack _packForFlow() {
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
        id: 'reading_micro_2',
        exerciseType: 'reading_micro',
        conceptId: 2,
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
        why: PilotWhy(reasons: const ['test'], signals: PilotWhySignals()),
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
            prompt: {'question': 'Which detail appears in the passage?'},
            choices: ['This is a story.', 'Another line.'],
            answerIndex: 0,
          ),
        ],
      ),
    ],
  );
}

void main() {
  testWidgets('Exam session flow start to finish', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: ExamSessionScreen(
          packOverride: _packForFlow(),
          configOverride: const ExamSchedulerConfig(
            duration: Duration(minutes: 1),
            totalCount: 2,
            skillWeights: {'vocab': 50, 'reading': 50},
            levelWeights: {1: 100, 2: 0, 3: 0},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Choose the meaning'), findsWidgets);
    await tester.tap(find.text('you'));
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.text('Read the passage and answer'), findsWidgets);
    await tester.tap(find.text('you'));
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();

    expect(find.text('Which detail appears in the passage?'), findsWidgets);
    await tester.tap(
      find.widgetWithText(MultipleChoiceOptionCard, 'This is a story.'),
    );
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pump();

    await tester.pumpAndSettle();
    expect(find.text('Exam readiness score'), findsOneWidget);
    expect(find.text('Measured proficiency'), findsOneWidget);
  });
}
