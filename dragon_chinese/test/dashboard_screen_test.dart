import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dragon_chinese/features/course/controllers/dashboard_controller.dart';
import 'package:dragon_chinese/features/course/models/lesson_model.dart';
import 'package:dragon_chinese/features/course/screens/dashboard_screen.dart';
import 'package:dragon_chinese/core/net/api_result.dart';

class _FakeDashboardController extends DashboardController {
  @override
  Future<ApiResult<DashboardData>> loadResult() async {
    return ApiSuccess(
      DashboardData(
        lessons: [
          Lesson(
            lessonId: 'lesson-1',
            vocabUnitId: 'unit-1',
            mode: 'intro',
            skillPrimary: 'Reading',
            estimatedTimeMinutes: 3,
            status: 'available',
            exerciseSequence: const [],
            metadata: const {
              'realm_title': 'Foundation Track',
              'unit_title': 'Basics',
              'type': 'intro',
            },
          ),
        ],
        masteryStats: const {},
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Header does not overflow on narrow widths', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(320, 640)),
        child: MaterialApp(
          home: DashboardScreen(
            currentSourceLang: 'en',
            onLanguageChanged: (_) {},
            controller: _FakeDashboardController(),
            showMissionCard: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final exception = tester.takeException();
    expect(exception, isNull);
  });

  testWidgets('Header does not overflow at 300 width', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(300, 640)),
        child: MaterialApp(
          home: DashboardScreen(
            currentSourceLang: 'en',
            onLanguageChanged: (_) {},
            controller: _FakeDashboardController(),
            showMissionCard: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final exception = tester.takeException();
    expect(exception, isNull);
  });

  testWidgets('Header does not overflow at 360 width', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(360, 640)),
        child: MaterialApp(
          home: DashboardScreen(
            currentSourceLang: 'en',
            onLanguageChanged: (_) {},
            controller: _FakeDashboardController(),
            showMissionCard: false,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final exception = tester.takeException();
    expect(exception, isNull);
  });

  testWidgets('Goal selection persists and updates goal chip', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'user_goal_profile_v1': 'professional',
    });

    await tester.pumpWidget(
      MaterialApp(
        home: DashboardScreen(
          currentSourceLang: 'en',
          onLanguageChanged: (_) {},
          controller: _FakeDashboardController(),
          showMissionCard: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Goal: Professional Focus'), findsOneWidget);
  });
}
