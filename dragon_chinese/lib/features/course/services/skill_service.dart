import 'dart:convert';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/core/network/api_client.dart';
import 'package:dragon_chinese/core/net/api_result.dart';
import 'package:dragon_chinese/core/net/endpoints.dart';
import 'package:dragon_chinese/features/course/models/study_session.dart';

class SkillGroup {
  final int level;
  final int count;
  final String label;
  final String description;

  SkillGroup({
    required this.level,
    required this.count,
    required this.label,
    required this.description,
  });

  factory SkillGroup.fromJson(Map<String, dynamic> json) {
    final level = _asInt(json['level']);
    final count = _asInt(json['count']);
    return SkillGroup(
      level: level,
      count: count,
      label: (json['label']?.toString().trim().isNotEmpty ?? false)
          ? json['label'].toString()
          : '${AppConfig.levelPrefix} $level',
      description: (json['description']?.toString().trim().isNotEmpty ?? false)
          ? json['description'].toString()
          : '$count words',
    );
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class VocabularyWord {
  final String word;
  final String pinyin;
  final String meaning;
  final String? imageUrl;
  final String? contextSentence;

  VocabularyWord({
    required this.word,
    required this.pinyin,
    required this.meaning,
    this.imageUrl,
    this.contextSentence,
  });

  factory VocabularyWord.fromJson(Map<String, dynamic> json) {
    final enMeaning = _extractMeaning(json);
    final word = _pickFirstNonEmpty([
      json['word']?.toString(),
      json['text']?.toString(),
      json['headword']?.toString(),
    ]);
    final pronunciation = _pickFirstNonEmpty([
      json['pronunciation']?.toString(),
      json['pinyin']?.toString(),
      '',
    ]);
    final sentence = _pickFirstNonEmpty([
      json['context_sentence']?.toString(),
      json['example_sentence']?.toString(),
      json['sentence']?.toString(),
    ]);

    return VocabularyWord(
      word: word,
      pinyin: pronunciation,
      meaning: enMeaning,
      imageUrl: json['image_url']?.toString(),
      contextSentence: sentence.isEmpty ? null : sentence,
    );
  }

  static String _extractMeaning(Map<String, dynamic> json) {
    final direct = _pickFirstNonEmpty([
      json['translation']?.toString(),
      json['meaning']?.toString(),
      json['definition']?.toString(),
    ]);
    if (direct.isNotEmpty) return direct;

    final translations = json['translations'];
    if (translations is Map) {
      final picked = _pickFromMap(translations);
      if (picked.isNotEmpty) return picked;
    }

    final defs = json['definitions'];
    if (defs is Map) {
      final picked = _pickFromMap(defs);
      if (picked.isNotEmpty) return picked;
    }
    if (defs is String && defs.trim().isNotEmpty) {
      try {
        final parsed = jsonDecode(defs);
        if (parsed is Map) {
          final picked = _pickFromMap(parsed);
          if (picked.isNotEmpty) return picked;
        }
      } catch (_) {
        return defs;
      }
      return defs;
    }

    return 'Unknown';
  }

  static String _pickFromMap(Map<dynamic, dynamic> map) {
    final english = map['en']?.toString().trim();
    if (english != null && english.isNotEmpty) return english;
    for (final value in map.values) {
      final v = value?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  static String _pickFirstNonEmpty(List<String?> values) {
    for (final value in values) {
      final v = value?.trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }
}

class SkillService {
  final ApiClient _api;
  SkillService({ApiClient? api}) : _api = api ?? ApiClient();

  Future<Map<String, double>> fetchMasteryStats() async {
    const fallback = <String, double>{
      'reading': 0.0,
      'writing': 0.0,
      'listening': 0.0,
      'speaking': 0.0,
      'vocabulary': 0.0,
    };

    final result = await _api.getJsonResult(Endpoints.skillsStats);
    if (result.isFailure) {
      // Stats are non-critical: keep dashboard alive even if this endpoint
      // temporarily fails (e.g. tunnel disconnect / flaky network).
      return fallback;
    }

    final data = (result as ApiSuccess<Map<String, dynamic>>).data;
    return {
      'reading': _asDouble(data['reading']),
      'writing': _asDouble(data['writing']),
      'listening': _asDouble(data['listening']),
      'speaking': _asDouble(data['speaking']),
      'vocabulary': _asDouble(data['vocabulary']),
    };
  }

  static double _asDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0.0;
  }

  Future<List<SkillGroup>> fetchSkillStats(
    String targetLang, {
    String sourceLang = 'en',
  }) async {
    final Map<String, dynamic> data = await _api.getJson(
      Endpoints.vocabularyStats,
      query: {'target_lang': targetLang, 'source_lang': sourceLang},
    );
    final List<dynamic> groups = (data['groups'] as List<dynamic>? ?? []);
    final parsed =
        groups
            .whereType<Map<String, dynamic>>()
            .map((g) => SkillGroup.fromJson(g))
            .toList()
          ..sort((a, b) => a.level.compareTo(b.level));
    return parsed;
  }

  Future<List<VocabularyWord>> fetchVocabularySet(
    int level,
    int offset,
    int limit, {
    String sourceLang = 'en',
    String? targetLang,
  }) async {
    final Map<String, dynamic> data = await _api.getJson(
      Endpoints.vocabulary,
      query: {
        'target_lang': targetLang ?? AppConfig.targetLang,
        'level': level.toString(),
        'limit': limit.toString(),
        'offset': offset.toString(),
        'source_lang': sourceLang,
      },
    );
    final List<dynamic> vocabList = data['vocabulary'];
    return vocabList.map((v) => VocabularyWord.fromJson(v)).toList();
  }

  Future<List<VocabularyWord>> fetchImageVocabulary(
    int level, {
    String sourceLang = 'en',
    String? targetLang,
  }) async {
    final Map<String, dynamic> data = await _api.getJson(
      Endpoints.vocabularyWithImages,
      query: {
        'target_lang': targetLang ?? AppConfig.targetLang,
        'level': level.toString(),
        'limit': '50',
        'source_lang': sourceLang,
      },
    );
    final List<dynamic> vocabList = data['vocabulary'];
    return vocabList.map((v) => VocabularyWord.fromJson(v)).toList();
  }

  /// Fetches personalized mission words from the Brain API.
  /// This uses the upgraded DeepSeek-R1 powered algorithm for optimal learning.
  Future<Map<String, dynamic>> fetchMissionWords({
    String userId = 'default_user',
    int limitNew = 5,
    int limitReview = 3,
    String? languageCode,
  }) async {
    // Keep method signature stable while backend derives user from headers.
    final _ = userId;
    final int totalLimit = (limitNew + limitReview).clamp(1, 20);
    final Map<String, dynamic> data = await _api.postJson(
      Endpoints.brainMission,
      body: {
        // user_id is derived from X-User-Id header on backend.
        'language_code': languageCode ?? AppConfig.targetLang,
        'intent': 'daily',
        'limit': totalLimit,
      },
    );
    return data;
  }

  /// Converts Brain API response words to VocabularyWord objects
  List<VocabularyWord> parseMissionWords(List<dynamic> words) {
    return words
        .map(
          (w) => VocabularyWord(
            word: w['headword'] ?? w['word'] ?? '',
            pinyin: w['pronunciation'] ?? '',
            meaning: w['translation'] ?? w['meaning'] ?? '',
            imageUrl: w['image_url'],
            contextSentence: w['context_sentence'],
          ),
        )
        .toList();
  }

  /// Fetches units list with progress and lock status
  Future<List<Map<String, dynamic>>> fetchUnits({
    String level = '${AppConfig.levelPrefix}1',
  }) async {
    final Map<String, dynamic> data = await _api.getJson(
      '/api/v2/path/units/list',
      query: {'level': level},
    );
    final List<dynamic> units = data['units'] ?? [];
    return units.cast<Map<String, dynamic>>();
  }

  /// Starts a Quick Study session with 5-10 words from a unit
  Future<StudySession> startQuickStudySession({
    required String unitId,
    int wordCount = 5,
  }) async {
    final Map<String, dynamic> data = await _api.postJson(
      '/api/v2/learning/session/start?unit_id=$unitId&word_count=$wordCount',
    );
    return StudySession.fromJson(data);
  }

  /// Completes a Quick Study session and updates mastery
  Future<Map<String, dynamic>> completeSession({
    required String sessionId,
    required Map<String, double> wordScores,
    required int timeSpentSeconds,
  }) async {
    final Map<String, dynamic> data = await _api.postJson(
      '/api/v2/learning/session/$sessionId/complete',
      body: {'word_scores': wordScores, 'time_spent_seconds': timeSpentSeconds},
    );
    return data;
  }
}
