import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/core/net/endpoints.dart';
import 'package:dragon_chinese/core/network/api_client.dart';
import 'package:dragon_chinese/core/utils/app_log.dart';

const String _expectedListeningSchemaVersion = '1.0';

class ListeningLevelGroup {
  final int level;
  final String label;
  final int totalWords;
  final int lessonCount;
  final String description;

  ListeningLevelGroup({
    required this.level,
    required this.label,
    required this.totalWords,
    required this.lessonCount,
    required this.description,
  });

  factory ListeningLevelGroup.fromJson(Map<String, dynamic> json) {
    return ListeningLevelGroup(
      level: _asInt(json['level']),
      label: (json['label']?.toString().trim().isNotEmpty ?? false)
          ? json['label'].toString()
          : 'Level ${_asInt(json['level'])}',
      totalWords: _asInt(json['total_words']),
      lessonCount: _asInt(json['lesson_count']),
      description: (json['description']?.toString().trim().isNotEmpty ?? false)
          ? json['description'].toString()
          : '${_asInt(json['lesson_count'])} listening lessons',
    );
  }
}

class ListeningLesson {
  final String id;
  final int level;
  final String label;
  final int lessonNumber;
  final String title;
  final String range;
  final int wordStart;
  final int wordEnd;
  final int wordCount;
  final int questionCount;
  final int durationSec;
  final String personaId;
  final String focusDimension;
  final String intent;
  final List<String> forcedIds;
  final int? targetMinSeconds;
  final int? targetMaxSeconds;

  ListeningLesson({
    required this.id,
    required this.level,
    required this.label,
    required this.lessonNumber,
    required this.title,
    required this.range,
    required this.wordStart,
    required this.wordEnd,
    required this.wordCount,
    required this.questionCount,
    required this.durationSec,
    required this.personaId,
    required this.focusDimension,
    required this.intent,
    required this.forcedIds,
    this.targetMinSeconds,
    this.targetMaxSeconds,
  });

  factory ListeningLesson.fromJson(Map<String, dynamic> json) {
    final launch =
        (json['launch'] as Map?)?.cast<String, dynamic>() ?? const {};
    return ListeningLesson(
      id: json['id']?.toString() ?? '',
      level: _asInt(json['level']),
      label: json['label']?.toString() ?? '',
      lessonNumber: _asInt(json['lesson_number']),
      title: json['title']?.toString() ?? '',
      range: json['range']?.toString() ?? '',
      wordStart: _asInt(json['word_start']),
      wordEnd: _asInt(json['word_end']),
      wordCount: _asInt(json['word_count']),
      questionCount: _asInt(json['question_count']),
      durationSec: _asInt(json['duration_sec']),
      personaId: json['persona_id']?.toString() ?? '',
      focusDimension:
          launch['focus_dimension']?.toString() ??
          json['focus_dimension']?.toString() ??
          'listening',
      intent:
          launch['intent']?.toString() ?? json['intent']?.toString() ?? 'drill',
      forcedIds:
          ((launch['forced_ids'] as List?) ??
                  (json['forced_ids'] as List?) ??
                  const [])
              .map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList(growable: false),
      targetMinSeconds: launch['target_min_seconds'] == null
          ? null
          : _asInt(launch['target_min_seconds']),
      targetMaxSeconds: launch['target_max_seconds'] == null
          ? null
          : _asInt(launch['target_max_seconds']),
    );
  }
}

class ListeningLessonDetail {
  final ListeningLesson lesson;

  ListeningLessonDetail({required this.lesson});

  factory ListeningLessonDetail.fromJson(Map<String, dynamic> json) {
    final lessonJson =
        (json['lesson'] as Map?)?.cast<String, dynamic>() ?? json;
    return ListeningLessonDetail(lesson: ListeningLesson.fromJson(lessonJson));
  }
}

class ListeningService {
  final ApiClient _api;

  ListeningService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<List<ListeningLevelGroup>> fetchLevels(
    String targetLang, {
    String sourceLang = 'en',
  }) async {
    final data = await _api.getJson(
      Endpoints.listeningLevels,
      query: {'target_lang': targetLang, 'source_lang': sourceLang},
    );
    _validateListeningSchema(data, endpoint: Endpoints.listeningLevels);
    final groups = (data['groups'] as List<dynamic>? ?? const []);
    return groups
        .whereType<Map<String, dynamic>>()
        .map(ListeningLevelGroup.fromJson)
        .toList()
      ..sort((a, b) => a.level.compareTo(b.level));
  }

  Future<List<ListeningLesson>> fetchLessonsForLevel({
    required int level,
    String sourceLang = 'en',
    String? targetLang,
  }) async {
    final data = await _api.getJson(
      Endpoints.listeningLessons,
      query: {
        'target_lang': targetLang ?? AppConfig.targetLang,
        'source_lang': sourceLang,
        'level': level.toString(),
      },
    );
    _validateListeningSchema(data, endpoint: Endpoints.listeningLessons);
    final lessons = (data['lessons'] as List<dynamic>? ?? const []);
    return lessons
        .whereType<Map<String, dynamic>>()
        .map(ListeningLesson.fromJson)
        .toList(growable: false);
  }

  Future<ListeningLessonDetail> fetchLessonDetail(
    String lessonId, {
    String sourceLang = 'en',
    String? targetLang,
  }) async {
    final data = await _api.getJson(
      '${Endpoints.listeningLessons}/$lessonId',
      query: {
        'target_lang': targetLang ?? AppConfig.targetLang,
        'source_lang': sourceLang,
      },
    );
    _validateListeningSchema(
      data,
      endpoint: '${Endpoints.listeningLessons}/$lessonId',
    );
    return ListeningLessonDetail.fromJson(data);
  }
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

void _validateListeningSchema(
  Map<String, dynamic> payload, {
  required String endpoint,
}) {
  final actual = payload['schema_version']?.toString().trim();
  if (actual == null || actual.isEmpty) {
    AppLog.w('Listening payload missing schema_version: $endpoint');
    return;
  }
  if (actual != _expectedListeningSchemaVersion) {
    AppLog.w(
      'Listening schema mismatch on $endpoint: expected=$_expectedListeningSchemaVersion actual=$actual',
    );
  }
}
