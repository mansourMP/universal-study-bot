import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/core/network/api_client.dart';
import 'package:dragon_chinese/core/net/api_result.dart';
import 'package:dragon_chinese/core/net/endpoints.dart';
import 'package:dragon_chinese/core/utils/app_log.dart';
import 'package:dragon_chinese/features/course/models/lesson_model.dart';

class LessonService {
  final ApiClient _api;
  LessonService({ApiClient? api}) : _api = api ?? ApiClient();

  /// Load lessons using typed ApiResult - no more silent failures
  Future<ApiResult<List<Lesson>>> loadLessonsResult() async {
    AppLog.d('Loading lessons from ${Endpoints.pathJourney}...');

    final result = await _api.getJsonResult(
      Endpoints.pathJourney,
      query: {'level': '1', 'target_lang': AppConfig.targetLang},
    );

    return result.fold(
      onSuccess: (data) {
        try {
          final List<dynamic> nodes = data['nodes'] ?? [];
          AppLog.i('Loaded ${nodes.length} lessons from server');

          final lessons = nodes.map((node) {
            final culturalNode = node['cultural'] ?? {};
            return Lesson(
              lessonId: node['id'],
              vocabUnitId: node['lesson_id'] ?? 'unknown',
              mode: node['type'] ?? 'standard',
              skillPrimary: 'vocabulary',
              estimatedTimeMinutes: node['estimated_minutes'] ?? 5,
              status: node['status'],
              unlockReason: node['unlock_reason'],
              masterySummary: node['mastery_summary'],
              cultural: LessonCultural(
                guideCharacter: node['guide_id'] ?? 'Sensei',
                setting: culturalNode['setting'] ?? 'Unit',
                storyContext:
                    culturalNode['story_context'] ?? node['subtitle'] ?? '',
                languageObjective:
                    culturalNode['language_objective'] ?? 'Master this unit',
              ),
              exerciseSequence: [],
              metadata: node['metadata'],
            );
          }).toList();

          return ApiSuccess(lessons);
        } catch (e, st) {
          AppLog.e('Failed to parse lessons', error: e, stackTrace: st);
          return ApiFailure(
            ApiErrorType.unknown,
            'Failed to parse lesson data',
            cause: e,
          );
        }
      },
      onFailure: (failure) {
        AppLog.e('Failed to load lessons', error: failure.message);
        return ApiFailure(
          failure.errorType,
          failure.message,
          statusCode: failure.statusCode,
          cause: failure.cause,
        );
      },
    );
  }

  /// Legacy method - kept for backwards compatibility
  /// WARNING: This silently returns empty list on failure - prefer loadLessonsResult()
  @Deprecated('Use loadLessonsResult() instead for proper error handling')
  Future<List<Lesson>> loadLessons() async {
    final result = await loadLessonsResult();
    return result.dataOrNull ?? [];
  }
}
