class AiExerciseSchema {
  final int schemaVersion;
  final String sourceProvider;
  final String generatedAt;
  final Map<String, dynamic> context;
  final List<AiExerciseItem> items;

  const AiExerciseSchema({
    required this.schemaVersion,
    required this.sourceProvider,
    required this.generatedAt,
    this.context = const {},
    this.items = const [],
  });

  factory AiExerciseSchema.fromJson(
    Map<String, dynamic> json, {
    String sourceProvider = 'unknown',
  }) {
    final container = _extractContainer(json);
    final itemsRaw = _extractItems(container);

    return AiExerciseSchema(
      schemaVersion:
          _asInt(container['schema_version'] ?? container['schemaVersion']) ??
          1,
      sourceProvider: _clean(
        container['source_provider'] ??
            container['sourceProvider'] ??
            sourceProvider,
      ),
      generatedAt: _clean(
        container['generated_at'] ??
            container['generatedAt'] ??
            DateTime.now().toUtc().toIso8601String(),
      ),
      context: _asMap(container['context']),
      items: List<AiExerciseItem>.generate(itemsRaw.length, (index) {
        return AiExerciseItem.fromJson(itemsRaw[index], fallbackIndex: index);
      }, growable: false),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schema_version': schemaVersion,
      'source_provider': sourceProvider,
      'generated_at': generatedAt,
      'context': context,
      'items': items.map((item) => item.toJson()).toList(growable: false),
    };
  }

  List<String> validate() {
    final issues = <String>[];

    if (schemaVersion <= 0) {
      issues.add('schema_version must be > 0');
    }
    if (sourceProvider.trim().isEmpty) {
      issues.add('source_provider is required');
    }
    if (items.isEmpty) {
      issues.add('items must contain at least one exercise');
    }

    for (var i = 0; i < items.length; i++) {
      issues.addAll(items[i].validate(i));
    }
    return issues;
  }

  static Map<String, dynamic> _extractContainer(Map<String, dynamic> raw) {
    final data = raw['data'];
    if (data is Map<String, dynamic>) {
      final hasItems = data['items'] is List || data['exercises'] is List;
      if (hasItems) return data;
    }
    final result = raw['result'];
    if (result is Map<String, dynamic>) {
      final hasItems = result['items'] is List || result['exercises'] is List;
      if (hasItems) return result;
    }
    return raw;
  }

  static List<Map<String, dynamic>> _extractItems(Map<String, dynamic> src) {
    final fromItems = src['items'];
    if (fromItems is List) {
      return fromItems
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    }

    final fromExercises = src['exercises'];
    if (fromExercises is List) {
      return fromExercises
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false);
    }

    final payload = src['payload'];
    if (payload is Map<String, dynamic>) {
      final nested = _extractItems(payload);
      if (nested.isNotEmpty) return nested;
    }

    return const <Map<String, dynamic>>[];
  }

  static String _clean(dynamic value) {
    final out = value?.toString().trim() ?? '';
    return out;
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final asText = value?.toString().trim() ?? '';
    if (asText.isEmpty) return null;
    return int.tryParse(asText);
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const <String, dynamic>{};
  }
}

class AiExerciseItem {
  final String id;
  final String exerciseType;
  final String skill;
  final String promptText;
  final List<String> choices;
  final int? answerIndex;
  final String? audioUrl;
  final String? imageUrl;
  final String? unitId;
  final int level;
  final Map<String, dynamic> meta;
  final Map<String, dynamic> payload;

  const AiExerciseItem({
    required this.id,
    required this.exerciseType,
    required this.skill,
    required this.promptText,
    this.choices = const [],
    this.answerIndex,
    this.audioUrl,
    this.imageUrl,
    this.unitId,
    this.level = 1,
    this.meta = const {},
    this.payload = const {},
  });

  factory AiExerciseItem.fromJson(
    Map<String, dynamic> json, {
    required int fallbackIndex,
  }) {
    final payload = _asMap(json['payload']);
    final mergedPayload = <String, dynamic>{...payload};

    for (final entry in json.entries) {
      if (entry.key == 'payload') continue;
      if (!mergedPayload.containsKey(entry.key)) {
        mergedPayload[entry.key] = entry.value;
      }
    }

    final choices = _extractChoices(json);
    final answerIndex = _extractAnswerIndex(json);

    return AiExerciseItem(
      id:
          _firstText(json, const [
            'id',
            'exercise_id',
            'item_id',
          ]).trim().isNotEmpty
          ? _firstText(json, const ['id', 'exercise_id', 'item_id']).trim()
          : 'ai_ex_${fallbackIndex + 1}',
      exerciseType: _firstText(json, const [
        'exercise_type',
        'type',
        'variant_id',
        'template_id',
      ]),
      skill: _firstText(json, const ['skill', 'subject']).isNotEmpty
          ? _firstText(json, const ['skill', 'subject'])
          : 'meaning',
      promptText: _firstText(json, const [
        'prompt_text',
        'question',
        'prompt',
        'instruction',
        'text',
        'sentence',
      ]),
      choices: choices,
      answerIndex: answerIndex,
      audioUrl: _optionalText(json, const ['audio_url', 'audioUrl', 'audio']),
      imageUrl: _optionalText(json, const ['image_url', 'imageUrl', 'image']),
      unitId: _optionalText(json, const ['unit_id', 'unitId']),
      level: _asInt(json['level']) ?? 1,
      meta: _asMap(json['meta']),
      payload: mergedPayload,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'exercise_type': exerciseType,
      'skill': skill,
      'prompt_text': promptText,
      'choices': choices,
      if (answerIndex != null) 'answer_index': answerIndex,
      if (audioUrl != null) 'audio_url': audioUrl,
      if (imageUrl != null) 'image_url': imageUrl,
      if (unitId != null) 'unit_id': unitId,
      'level': level,
      'meta': meta,
      'payload': payload,
    };
  }

  List<String> validate(int index) {
    final issues = <String>[];
    final label = 'item[$index]';

    if (id.trim().isEmpty) {
      issues.add('$label.id is required');
    }
    if (exerciseType.trim().isEmpty) {
      issues.add('$label.exercise_type is required');
    }
    if (level <= 0) {
      issues.add('$label.level must be > 0');
    }

    if (choices.isNotEmpty) {
      final idx = answerIndex;
      if (idx == null) {
        issues.add('$label.answer_index is required when choices are present');
      } else if (idx < 0 || idx >= choices.length) {
        issues.add('$label.answer_index out of bounds for choices');
      }
    }

    if (_choiceRequiredTypes.contains(exerciseType) && choices.isEmpty) {
      issues.add('$label.choices must not be empty for $exerciseType');
    }

    return issues;
  }

  static const Set<String> _choiceRequiredTypes = <String>{
    'meaning_select',
    'character_select',
    'pinyin_select',
    'reply_select',
    'conversation_simulation',
    'audio_select',
    'dictation_select',
    'reading_micro',
    'reading_span_select',
    'cloze_select',
    'true_false',
  };

  static List<String> _extractChoices(Map<String, dynamic> json) {
    final direct = _extractStringList(json['choices']);
    if (direct.isNotEmpty) return direct;

    final optionsRaw = json['options'];
    if (optionsRaw is List) {
      final out = <String>[];
      for (final raw in optionsRaw) {
        if (raw is String) {
          final clean = raw.trim();
          if (clean.isNotEmpty) out.add(clean);
          continue;
        }
        if (raw is Map) {
          final map = raw.cast<String, dynamic>();
          final text = _firstText(map, const ['text', 'label', 'value']);
          if (text.trim().isNotEmpty) {
            out.add(text.trim());
          }
        }
      }
      if (out.isNotEmpty) return out;
    }

    return const <String>[];
  }

  static int? _extractAnswerIndex(Map<String, dynamic> json) {
    final direct = _asInt(json['answer_index'] ?? json['correct_index']);
    if (direct != null) return direct;

    final correctId = _optionalText(json, const ['correct_option_id']);
    if (correctId == null || correctId.isEmpty) return null;

    final optionsRaw = json['options'];
    if (optionsRaw is! List) return null;

    for (var i = 0; i < optionsRaw.length; i++) {
      final raw = optionsRaw[i];
      if (raw is! Map) continue;
      final map = raw.cast<String, dynamic>();
      final id = map['id']?.toString().trim() ?? '';
      if (id == correctId) return i;
    }
    return null;
  }

  static String _firstText(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      final value = json[key];
      if (value == null) continue;
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value is Map || value is List) continue;
      final asText = value.toString().trim();
      if (asText.isNotEmpty) return asText;
    }
    return '';
  }

  static String? _optionalText(Map<String, dynamic> json, List<String> keys) {
    final out = _firstText(json, keys);
    return out.isEmpty ? null : out;
  }

  static List<String> _extractStringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final asText = value?.toString().trim() ?? '';
    if (asText.isEmpty) return null;
    return int.tryParse(asText);
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const <String, dynamic>{};
  }
}
