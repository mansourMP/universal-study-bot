import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/screens/practice_session_screen.dart';
import 'package:dragon_chinese/features/course/services/practice_state_store.dart';

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
    ],
  );
}

void main() {
  testWidgets('PracticeSessionScreen does not overflow at 320 width', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final errors = <FlutterErrorDetails>[];
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
    };
    addTearDown(() => FlutterError.onError = original);

    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: PracticeSessionScreen(
          packOverride: _pack(),
          stateOverride: PracticeStateStore.fromData(),
          seed: 'seed',
          dateBucket: '2026-02-03',
        ),
      ),
    );

    await tester.pumpAndSettle();

    final overflowErrors = errors.where(
      (e) => e.exceptionAsString().contains('overflowed'),
    );
    expect(overflowErrors.isEmpty, true);
  });
}
