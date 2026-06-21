import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/widgets/path_components.dart';
import 'package:dragon_chinese/features/course/adapters/path_view_models.dart';
import 'package:dragon_chinese/design_system/path_theme.dart';

void main() {
  testWidgets('UnitHeaderCard shows progress label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: UnitHeaderCard(
            title: 'Unit 1',
            subtitle: 'Basics',
            completed: 3,
            total: 10,
            isCurrent: true,
            focusLabel: 'Professional Focus',
          ),
        ),
      ),
    );

    expect(find.text('3/10'), findsOneWidget);
    expect(find.text('Current unit'), findsOneWidget);
  });

  testWidgets('LessonCard shows correct status pill', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonCard(
            title: 'Lesson 1',
            promise: 'Practice core phrases',
            timeLabel: '3 min',
            icon: Icons.menu_book_rounded,
            isLocked: false,
            isCompleted: false,
            isCurrent: true,
            onTap: () {},
            chips: const [],
            progress: 0.2,
            statusLabel: 'Continue',
            imageUrl: null,
            hasAudio: false,
          ),
        ),
      ),
    );

    expect(find.text('CONTINUE'), findsOneWidget);

    final containers = tester.widgetList<Container>(
      find.ancestor(
        of: find.text('CONTINUE'),
        matching: find.byType(Container),
      ),
    );
    final matches = containers.where((container) {
      final decoration = container.decoration;
      if (decoration is! BoxDecoration) return false;
      return decoration.color == PathThemeTokens.brandAccent;
    });
    expect(matches.length, 1);
  });

  testWidgets('Progress rail renders correct node icons', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              ProgressRailNode(
                state: LessonState.completed,
                isFirst: true,
                isLast: false,
              ),
              ProgressRailNode(
                state: LessonState.current,
                isFirst: false,
                isLast: false,
              ),
              ProgressRailNode(
                state: LessonState.locked,
                isFirst: false,
                isLast: true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.circle), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  testWidgets('Locked lesson remains readable (opacity not too low)',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonCard(
            title: 'Locked Lesson',
            promise: 'Practice core phrases',
            timeLabel: '',
            icon: Icons.menu_book_rounded,
            isLocked: true,
            isCompleted: false,
            isCurrent: false,
            onTap: null,
            chips: const [],
            progress: 0,
            statusLabel: 'Locked',
            imageUrl: null,
            hasAudio: false,
          ),
        ),
      ),
    );

    final opacityWidget = tester.widget<Opacity>(find.byType(Opacity).first);
    expect(opacityWidget.opacity, greaterThanOrEqualTo(0.75));
  });

  testWidgets('Sync banner triggers retry callback', (tester) async {
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncBanner(
            onRetry: () {
              called = true;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(called, isTrue);
  });
}
