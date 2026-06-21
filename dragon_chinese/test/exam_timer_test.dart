import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/screens/exam_session_screen.dart';
import 'package:dragon_chinese/features/course/services/exam_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

PilotExerciseItem _timedItem({required bool timed}) {
  return PilotExerciseItem(
    id: 'meaning_select_1',
    exerciseType: 'meaning_select',
    conceptId: 1,
    unitId: '1',
    level: 3,
    skill: 'vocab',
    constraints: PilotConstraints(
      timedSec: timed ? 20 : null,
      retryPolicy: 'none',
    ),
    prompt: const PilotPrompt(hanzi: '你', pinyin: 'ni', meaning: 'you'),
    choices: const ['you', 'me'],
    answerIndex: 0,
    options: const [],
    correctOptionId: null,
    meta: PilotMeta(hskLevel: 1, unitId: '1', tags: const []),
    payload: const {},
    questions: const [],
  );
}

void main() {
  testWidgets('Timer bar renders when timedSec exists', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final pack = PilotExercisePack(
      schemaVersion: 3,
      generatedAt: '2026-02-02',
      items: [_timedItem(timed: true)],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExamSessionScreen(
          packOverride: pack,
          configOverride: const ExamSchedulerConfig(
            duration: Duration(minutes: 1),
            totalCount: 1,
            skillWeights: {'vocab': 100},
            levelWeights: {3: 100},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.textContaining('Time left'), findsOneWidget);
  });

  testWidgets('Timer bar hidden when timedSec absent', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final pack = PilotExercisePack(
      schemaVersion: 3,
      generatedAt: '2026-02-02',
      items: [_timedItem(timed: false)],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExamSessionScreen(
          packOverride: pack,
          configOverride: const ExamSchedulerConfig(
            duration: Duration(minutes: 1),
            totalCount: 1,
            skillWeights: {'vocab': 100},
            levelWeights: {1: 100},
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.textContaining('Time left'), findsNothing);
  });
}
