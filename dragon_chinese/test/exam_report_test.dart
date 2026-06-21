import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/screens/exam_report_screen.dart';

void main() {
  testWidgets('ExamReportScreen renders breakdown and CTA', (tester) async {
    final item = PilotExerciseItem(
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
      payload: const {},
      questions: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: ExamReportScreen(
          attempts: [
            ExamAttempt(
              item: item,
              isCorrect: true,
              latencyMs: 1200,
              timedOverrun: false,
            ),
            ExamAttempt(
              item: item,
              isCorrect: false,
              latencyMs: 2200,
              timedOverrun: false,
            ),
          ],
          sessionDuration: const Duration(minutes: 18),
          seed: 'test-seed',
        ),
      ),
    );

    expect(find.text('Exam readiness score'), findsOneWidget);
    expect(find.text('Skill breakdown'), findsOneWidget);
    expect(find.text('Mistakes to revisit'), findsOneWidget);
    expect(find.textContaining('Next best drill'), findsOneWidget);
  });
}
