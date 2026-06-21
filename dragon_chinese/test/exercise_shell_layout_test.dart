import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_shell.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_media.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/multiple_choice_exercise.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> _pumpShell(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(width, 720)),
        child: MaterialApp(
          home: ExerciseShell(
            index: 0,
            total: 20,
            attemptsRemaining: 3,
            attemptsTotal: 3,
            isAnswered: false,
            isCorrect: false,
            isReady: true,
            timerRemainingSec: 32,
            timerTotalSec: 60,
            instruction: 'Choose the best meaning for the highlighted word.',
            subInstruction: 'Focus on accuracy before speed.',
            skillLabel: 'Meaning',
            levelLabel: 'L1',
            mediaSlot: const ExerciseMediaSlot(
              showImagePlaceholder: true,
              showAudio: true,
            ),
            content: Column(
              children: const [
                MultipleChoiceOptionCard(
                  label: 'Option A',
                  isSelected: false,
                  isCorrect: false,
                  isAnswered: false,
                ),
                SizedBox(height: 10),
                MultipleChoiceOptionCard(
                  label: 'Option B',
                  isSelected: false,
                  isCorrect: false,
                  isAnswered: false,
                ),
              ],
            ),
            onCheck: () {},
            onContinue: () {},
            onTryAgain: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('ExerciseShell layout does not overflow at small widths',
      (WidgetTester tester) async {
    for (final width in [300.0, 320.0, 360.0]) {
      await _pumpShell(tester, width);
      final exception = tester.takeException();
      expect(exception, isNull, reason: 'Overflow at width $width');
    }
  });
}