import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_shell.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/speaking_exercise.dart';

void main() {
  testWidgets('Speaking layout does not overflow at 320 width', (tester) async {
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
        home: ExerciseShell(
          index: 3,
          total: 10,
          sectionLabel: 'Speaking',
          skillLabel: 'Speaking',
          skillIcon: Icons.mic_rounded,
          instruction: 'Read aloud and self-rate',
          levelLabel: 'L1',
          attemptsRemaining: 2,
          attemptsTotal: 2,
          isAnswered: false,
          isCorrect: false,
          isReady: true,
          primaryLabelOverride: 'Continue',
          primaryEnabledOverride: false,
          onPrimaryOverride: () {},
          onCheck: () {},
          onContinue: () {},
          onTryAgain: () {},
          content: SpeakReadAloudExercise(
            hanzi: '你好',
            pinyin: 'ni hao',
            sampleAnswers: const ['你好'],
            permissionGranted: true,
            isRecording: false,
            durationMs: null,
            rating: null,
            onRequestPermission: () {},
            onStartRecording: () {},
            onStopRecording: () {},
            onRate: (_) {},
          ),
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
