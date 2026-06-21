import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/design_system/pressable_keycap.dart';
import 'package:dragon_chinese/design_system/exercise_theme.dart';

void _noop() {}

void main() {
  testWidgets('PressableKeycap animates face translation on press', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressableCtaButton(
              label: 'Check',
              onTap: _noop,
            ),
          ),
        ),
      ),
    );

    AnimatedPositioned positioned =
        tester.widget(find.byType(AnimatedPositioned).first);
    expect(positioned.top, 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PressableCtaButton)),
    );
    await tester.pump();

    positioned = tester.widget(find.byType(AnimatedPositioned).first);
    expect(positioned.top, ExerciseThemeTokens.keycapDepth);

    await gesture.up();
    await tester.pump();

    positioned = tester.widget(find.byType(AnimatedPositioned).first);
    expect(positioned.top, 0);
  });
}
