import 'dart:convert';

import 'package:dragon_chinese/core/net/endpoints.dart';
import 'package:dragon_chinese/core/network/api_client.dart';
import 'package:dragon_chinese/features/course/services/listening_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ListeningService', () {
    test(
      'fetchLevels calls listening levels endpoint and parses groups',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.url.path, equals(Endpoints.listeningLevels));
          expect(request.url.queryParameters['target_lang'], equals('zh'));
          expect(request.url.queryParameters['source_lang'], equals('en'));
          return http.Response(
            jsonEncode({
              'schema_version': '1.0',
              'target_lang': 'zh',
              'source_lang': 'en',
              'chunk_size': 12,
              'groups': [
                {
                  'level': 3,
                  'label': 'HSK 3',
                  'total_words': 600,
                  'lesson_count': 50,
                  'description': '50 listening lessons',
                },
                {
                  'level': 2,
                  'label': 'HSK 2',
                  'total_words': 300,
                  'lesson_count': 25,
                  'description': '25 listening lessons',
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = ListeningService(api: ApiClient(client: mockClient));
        final groups = await service.fetchLevels('zh', sourceLang: 'en');

        expect(groups.length, equals(2));
        // Service sorts ascending by level.
        expect(groups.first.level, equals(2));
        expect(groups.last.level, equals(3));
        expect(groups.first.label, equals('HSK 2'));
        expect(groups.first.totalWords, equals(300));
        expect(groups.first.lessonCount, equals(25));
      },
    );

    test(
      'fetchLessonsForLevel parses launch-configured lesson fields',
      () async {
        final mockClient = MockClient((request) async {
          expect(request.url.path, equals(Endpoints.listeningLessons));
          expect(request.url.queryParameters['target_lang'], equals('zh'));
          expect(request.url.queryParameters['source_lang'], equals('en'));
          expect(request.url.queryParameters['level'], equals('2'));
          return http.Response(
            jsonEncode({
              'schema_version': '1.0',
              'target_lang': 'zh',
              'source_lang': 'en',
              'level': 2,
              'label': 'HSK 2',
              'chunk_size': 12,
              'total_words': 300,
              'lessons': [
                {
                  'id': 'LIS_HSK2_001',
                  'level': 2,
                  'label': 'HSK 2',
                  'lesson_number': 1,
                  'title': 'Listening 1',
                  'range': '1-12',
                  'word_start': 1,
                  'word_end': 12,
                  'word_count': 12,
                  'question_count': 5,
                  'duration_sec': 120,
                  'persona_id': 'creator_01',
                  'focus_dimension': 'listening',
                  'intent': 'drill',
                  'forced_ids': ['W1'],
                  'launch': {
                    'intent': 'drill',
                    'focus_dimension': 'listening',
                    'exercise_count': 5,
                    'forced_ids': ['W1', 'W2', 'W3'],
                    'target_min_seconds': 120,
                    'target_max_seconds': 150,
                  },
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = ListeningService(api: ApiClient(client: mockClient));
        final lessons = await service.fetchLessonsForLevel(
          level: 2,
          sourceLang: 'en',
          targetLang: 'zh',
        );

        expect(lessons.length, equals(1));
        final lesson = lessons.first;
        expect(lesson.id, equals('LIS_HSK2_001'));
        expect(lesson.level, equals(2));
        expect(lesson.focusDimension, equals('listening'));
        expect(lesson.intent, equals('drill'));
        // launch.forced_ids should take precedence.
        expect(lesson.forcedIds, equals(['W1', 'W2', 'W3']));
        expect(lesson.targetMinSeconds, equals(120));
        expect(lesson.targetMaxSeconds, equals(150));
      },
    );

    test(
      'fetchLessonDetail calls lesson detail route and parses lesson',
      () async {
        final mockClient = MockClient((request) async {
          expect(
            request.url.path,
            equals('${Endpoints.listeningLessons}/LIS_HSK2_001'),
          );
          expect(request.url.queryParameters['target_lang'], equals('zh'));
          expect(request.url.queryParameters['source_lang'], equals('en'));
          return http.Response(
            jsonEncode({
              'schema_version': '1.0',
              'lesson': {
                'id': 'LIS_HSK2_001',
                'level': 2,
                'label': 'HSK 2',
                'lesson_number': 1,
                'title': 'Listening 1',
                'range': '1-12',
                'word_start': 1,
                'word_end': 12,
                'word_count': 12,
                'question_count': 5,
                'duration_sec': 120,
                'persona_id': 'mentor_01',
                'launch': {
                  'intent': 'drill',
                  'focus_dimension': 'listening',
                  'exercise_count': 5,
                  'forced_ids': ['W1', 'W2'],
                  'target_min_seconds': 120,
                  'target_max_seconds': 150,
                },
              },
              'mission': {'intent': 'drill', 'focus_dimension': 'listening'},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        });

        final service = ListeningService(api: ApiClient(client: mockClient));
        final detail = await service.fetchLessonDetail(
          'LIS_HSK2_001',
          sourceLang: 'en',
          targetLang: 'zh',
        );

        expect(detail.lesson.id, equals('LIS_HSK2_001'));
        expect(detail.lesson.personaId, equals('mentor_01'));
        expect(detail.lesson.forcedIds, equals(['W1', 'W2']));
      },
    );
  });
}
