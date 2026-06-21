import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/screens/readiness_screen.dart';
import 'package:dragon_chinese/features/course/widgets/path_components.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> _pumpReadinessScore(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(width, 640)),
        child: MaterialApp(
          home: Scaffold(
            body: ReadinessScoreCard(overall: 68, label: 'On track'),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> _pumpReadinessCard(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: Size(width, 640)),
        child: MaterialApp(
          home: Scaffold(
            body: ReadinessCard(
              score: 64,
              label: 'Needs work',
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('Readiness cards do not overflow at small widths',
      (WidgetTester tester) async {
    for (final width in [300.0, 320.0, 360.0]) {
      await _pumpReadinessScore(tester, width);
      expect(tester.takeException(), isNull, reason: 'Score card overflow at $width');
      await _pumpReadinessCard(tester, width);
      expect(tester.takeException(), isNull, reason: 'Path card overflow at $width');
    }
  });
}
