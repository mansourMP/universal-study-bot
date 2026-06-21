import 'package:dragon_chinese/core/net/api_result.dart';
import 'package:dragon_chinese/features/course/models/lesson_model.dart';
import 'package:dragon_chinese/features/course/services/lesson_service.dart';
import 'package:dragon_chinese/features/course/services/skill_service.dart';

class DashboardData {
  final List<Lesson> lessons;
  final Map<String, double> masteryStats;

  const DashboardData({required this.lessons, required this.masteryStats});
}

class DashboardController {
  final LessonService _lessons;
  final SkillService _skills;

  DashboardController({LessonService? lessons, SkillService? skills})
    : _lessons = lessons ?? LessonService(),
      _skills = skills ?? SkillService();

  /// Load dashboard data with typed result
  Future<ApiResult<DashboardData>> loadResult() async {
    // Load lessons with proper error handling
    final lessonsResult = await _lessons.loadLessonsResult();

    if (lessonsResult.isFailure) {
      final failure = lessonsResult as ApiFailure;
      return ApiFailure(
        failure.errorType,
        failure.message,
        statusCode: failure.statusCode,
        cause: failure.cause,
      );
    }

    final lessons = (lessonsResult as ApiSuccess<List<Lesson>>).data;

    // Load mastery stats (non-critical, use defaults on failure)
    Map<String, double> mastery;
    try {
      mastery = await _skills.fetchMasteryStats();
    } catch (_) {
      mastery = const {
        'reading': 0.0,
        'writing': 0.0,
        'listening': 0.0,
        'speaking': 0.0,
        'vocabulary': 0.0,
      };
    }
    final normalized = {
      'reading': mastery['reading'] ?? 0.0,
      'writing': mastery['writing'] ?? 0.0,
      'listening': mastery['listening'] ?? 0.0,
      'speaking': mastery['speaking'] ?? 0.0,
      'vocabulary': mastery['vocabulary'] ?? 0.0,
    };

    return ApiSuccess(
      DashboardData(lessons: lessons, masteryStats: normalized),
    );
  }

  /// Legacy method - kept for backwards compatibility
  @Deprecated('Use loadResult() instead for proper error handling')
  Future<DashboardData> load() async {
    final result = await loadResult();
    if (result.isFailure) {
      throw (result as ApiFailure).toException();
    }
    return (result as ApiSuccess<DashboardData>).data;
  }
}
