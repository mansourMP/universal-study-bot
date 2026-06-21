import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/screens/exam_session_screen.dart';
import 'package:dragon_chinese/features/course/services/exam_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

PilotExercisePack _packWithPlaceholderAudio() {
  return PilotExercisePack(
    schemaVersion: 3,
    generatedAt: '2026-02-03',
    items: [
      PilotExerciseItem(
        id: 'audio_select_1',
        exerciseType: 'audio_select',
        conceptId: 1,
        unitId: '1',
        level: 1,
        skill: 'listening',
        constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
        attemptsAllowed: 2,
        prompt: const PilotPrompt(hanzi: '你', pinyin: 'ni', meaning: 'you'),
        choices: const ['你', '我', '他', '她'],
        answerIndex: 0,
        options: const [],
        correctOptionId: null,
        meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
        why: PilotWhy(reasons: const ['test'], signals: PilotWhySignals()),
        audioUrl: '/api/v2/audio/_placeholder_template.mp3',
        payload: const {},
        questions: const [],
        requiredAssets: const PilotRequiredAssets(audio: true, image: false),
      ),
      PilotExerciseItem(
        id: 'meaning_select_2',
        exerciseType: 'meaning_select',
        conceptId: 2,
        unitId: '1',
        level: 1,
        skill: 'vocab',
        constraints: PilotConstraints(timedSec: null, retryPolicy: 'none'),
        attemptsAllowed: 2,
        prompt: const PilotPrompt(hanzi: '好', pinyin: 'hao', meaning: 'good'),
        choices: const ['good', 'bad'],
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
  testWidgets('Exam skips placeholder audio items deterministically', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: ExamSessionScreen(
          packOverride: _packWithPlaceholderAudio(),
          configOverride: const ExamSchedulerConfig(
            duration: Duration(minutes: 1),
            totalCount: 2,
            skillWeights: {'listening': 50, 'vocab': 50},
            levelWeights: {1: 100},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Should skip audio_select and render meaning_select.
    expect(find.text('Choose the meaning'), findsWidgets);
  });
}
