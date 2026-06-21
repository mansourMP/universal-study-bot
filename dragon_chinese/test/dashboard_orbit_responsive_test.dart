import 'package:dragon_chinese/core/net/api_result.dart';
import 'package:dragon_chinese/features/course/controllers/dashboard_controller.dart';
import 'package:dragon_chinese/features/course/models/lesson_model.dart';
import 'package:dragon_chinese/features/course/screens/dashboard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OrbitFakeDashboardController extends DashboardController {
  @override
  Future<ApiResult<DashboardData>> loadResult() async {
    List<Lesson> lessons = List.generate(5, (index) {
      final status = index == 0
          ? 'available'
          : (index < 3 ? 'completed' : 'locked');
      return Lesson(
        lessonId: 'lesson-${index + 1}',
        vocabUnitId: 'unit-1',
        mode: 'intro',
        skillPrimary: 'vocabulary',
        estimatedTimeMinutes: 5,
        status: status,
        exerciseSequence: const [],
        metadata: const {
          'realm_title': 'Foundation Track',
          'unit_title': 'Basics',
        },
      );
    });

    return ApiSuccess(DashboardData(lessons: lessons, masteryStats: const {}));
  }
}

Future<void> _pumpOrbit(WidgetTester tester, Size size) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: MaterialApp(
        home: DashboardScreen(
          currentSourceLang: 'en',
          onLanguageChanged: (_) {},
          controller: OrbitFakeDashboardController(),
          showMissionCard: false,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 80));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Orbit has no overflow at 360x800', (tester) async {
    await _pumpOrbit(tester, const Size(360, 800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Orbit has no overflow at 800x600', (tester) async {
    await _pumpOrbit(tester, const Size(800, 600));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Orbit has no overflow at 1200x800', (tester) async {
    await _pumpOrbit(tester, const Size(1200, 800));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Skills tab is reachable from PATH toggle', (tester) async {
    await _pumpOrbit(tester, const Size(800, 600));
    expect(find.text('SKILLS'), findsOneWidget);

    await tester.tap(find.text('SKILLS'));
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Vocabulary'), findsOneWidget);
    expect(find.text('Quick Study'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
