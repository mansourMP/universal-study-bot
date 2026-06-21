import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/screens/practice_summary_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> _pumpSummary(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(width, 720)),
        child: MaterialApp(
          home: PracticeSummaryScreen(
            attempts: [
              PracticeAttempt(skill: 'meaning', isCorrect: true),
              PracticeAttempt(skill: 'meaning', isCorrect: false),
              PracticeAttempt(skill: 'listening', isCorrect: true),
              PracticeAttempt(skill: 'reading', isCorrect: false),
            ],
            onDrillAgain: () {},
            onFixMistakes: () {},
            onWeakSkillDrill: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Practice summary layout does not overflow at small widths',
      (WidgetTester tester) async {
    for (final width in [300.0, 320.0, 360.0]) {
      await _pumpSummary(tester, width);
      final exception = tester.takeException();
      expect(exception, isNull, reason: 'Overflow at width $width');
    }
  });
}
