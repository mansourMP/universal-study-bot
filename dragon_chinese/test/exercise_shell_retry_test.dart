import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_shell.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/multiple_choice_exercise.dart';

class _RetryHarness extends StatefulWidget {
  const _RetryHarness();

  @override
  State<_RetryHarness> createState() => _RetryHarnessState();
}

class _RetryHarnessState extends State<_RetryHarness> {
  int? selectedIndex;
  bool isAnswered = false;
  bool isCorrect = false;
  int attemptsRemaining = 3;
  String? hint;
  String? reveal;

  void _check() {
    isCorrect = selectedIndex == 0;
    if (!isCorrect && attemptsRemaining > 0) {
      attemptsRemaining -= 1;
    }
    hint = !isCorrect ? 'Hint: starts with A' : null;
    reveal = (!isCorrect && attemptsRemaining == 0) ? 'Correct: A' : null;
    setState(() => isAnswered = true);
  }

  void _tryAgain() {
    setState(() {
      selectedIndex = null;
      isAnswered = false;
      hint = null;
      reveal = null;
    });
  }

  void _continue() {}

  @override
  Widget build(BuildContext context) {
    return ExerciseShell(
      index: 0,
      total: 1,
      attemptsRemaining: attemptsRemaining,
      attemptsTotal: 3,
      isAnswered: isAnswered,
      isCorrect: isCorrect,
      isReady: selectedIndex != null,
      hint: hint,
      revealText: reveal,
      onCheck: _check,
      onTryAgain: _tryAgain,
      onContinue: _continue,
      content: Column(
        children: [
          MultipleChoiceOptionCard(
            label: 'A',
            isSelected: selectedIndex == 0,
            isCorrect: true,
            isAnswered: isAnswered,
            onTap: () => setState(() => selectedIndex = 0),
          ),
          const SizedBox(height: 8),
          MultipleChoiceOptionCard(
            label: 'B',
            isSelected: selectedIndex == 1,
            isCorrect: false,
            isAnswered: isAnswered,
            onTap: () => setState(() => selectedIndex = 1),
          ),
        ],
      ),
    );
  }
}

void main() {
  testWidgets('Retry loop allows 3 attempts then reveal', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _RetryHarness()));

    // Attempt 1: Wrong
    await tester.tap(find.text('B'));
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Try Again'), findsOneWidget); // Case sensitive now
    await tester.tap(find.text('Try Again'));
    await tester.pump();
    await tester.pumpAndSettle();

    // Attempt 2: Wrong
    await tester.tap(find.text('B'));
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Try Again'), findsOneWidget);
    await tester.tap(find.text('Try Again'));
    await tester.pump();
    await tester.pumpAndSettle();

    // Attempt 3: Wrong (Fail)
    await tester.tap(find.text('B'));
    await tester.pump();
    await tester.tap(find.text('Check'));
    await tester.pump();
    await tester.pumpAndSettle();

    // Reveal
    expect(find.textContaining('Correct:'), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });
}