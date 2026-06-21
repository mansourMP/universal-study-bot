import 'dart:convert';

class PilotExercisePack {
  final int schemaVersion;
  final String generatedAt;
  final List<PilotExerciseItem> items;

  PilotExercisePack({
    required this.schemaVersion,
    required this.generatedAt,
    required this.items,
  });

  factory PilotExercisePack.fromJson(Map<String, dynamic> json) {
    final itemsJson = (json['items'] as List<dynamic>? ?? []);
    return PilotExercisePack(
      schemaVersion: json['schema_version'] ?? 1,
      generatedAt: json['generated_at'] ?? '',
      items: itemsJson
          .map((e) => PilotExerciseItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  static PilotExercisePack fromRawJson(String raw) {
    return PilotExercisePack.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

class PilotExerciseItem {
  final String id;
  final String templateId;
  final String variantId;
  final String exerciseType;
  final int conceptId;
  final String? unitId;
  final int level;
  final String skill;
  final PilotConstraints constraints;
  final int attemptsAllowed;
  final int? timeLimitMs;
  final int difficultyLevel;
  final PilotRequiredAssets requiredAssets;
  final String? promptText;
  final PilotPrompt prompt;
  final List<String> choices;
  final int answerIndex;
  final List<PilotOption> options;
  final String? correctOptionId;
  final PilotMeta meta;
  final PilotWhy? why;
  final String? audioUrl;
  final String? choiceType;
  final Map<String, dynamic> payload;
  final PilotReading? reading;
  final List<PilotQuestion> questions;

  PilotExerciseItem({
    required this.id,
    this.templateId = '',
    this.variantId = '',
    required this.exerciseType,
    required this.conceptId,
    required this.unitId,
    required this.level,
    required this.skill,
    required this.constraints,
    this.attemptsAllowed = 3,
    this.timeLimitMs,
    this.difficultyLevel = 1,
    this.requiredAssets = const PilotRequiredAssets(audio: false, image: false),
    this.promptText,
    required this.prompt,
    required this.choices,
    required this.answerIndex,
    required this.options,
    this.correctOptionId,
    required this.meta,
    this.why,
    this.audioUrl,
    this.choiceType,
    required this.payload,
    this.reading,
    required this.questions,
  });

  factory PilotExerciseItem.fromJson(Map<String, dynamic> json) {
    final metaJson = (json['meta'] as Map<String, dynamic>? ?? const {});
    final templateId = (json['template_id']?.toString() ?? '').trim();
    final variantIdRaw = (json['variant_id']?.toString() ?? '').trim();
    final exerciseTypeRaw = (json['exercise_type']?.toString() ?? '').trim();
    final resolvedVariant = variantIdRaw.isNotEmpty
        ? variantIdRaw
        : (exerciseTypeRaw.isNotEmpty
              ? exerciseTypeRaw
              : _defaultVariantForTemplate(templateId));

    final payload = (json['payload'] as Map<String, dynamic>? ?? const {});
    final questionsJson =
        (json['questions'] as List<dynamic>? ??
        (payload['questions'] as List<dynamic>? ?? []));
    final readingRaw = json['reading'] ?? payload['reading'];
    final whyRaw = json['why'] as Map<String, dynamic>?;
    final optionsRaw = (json['options'] as List<dynamic>? ?? const []);
    final options = optionsRaw
        .whereType<Map<String, dynamic>>()
        .map(PilotOption.fromJson)
        .toList();
    final correctOptionId = json['correct_option_id']?.toString();
    final interaction =
        (json['interaction'] as Map<String, dynamic>? ?? const {});
    final choicesRaw = _extractChoices(
      choices: json['choices'],
      options: options,
      interaction: interaction,
    );
    var answerIndex = _extractAnswerIndex(
      rawAnswerIndex: json['answer_index'],
      interaction: interaction,
      evaluation: (json['evaluation'] as Map<String, dynamic>? ?? const {}),
    );
    var choices = choicesRaw;
    if (options.isNotEmpty && choices.isEmpty) {
      choices = options.map((o) => o.text).toList();
      if (correctOptionId != null) {
        final idx = options.indexWhere((o) => o.id == correctOptionId);
        if (idx >= 0) {
          answerIndex = idx;
        }
      }
    }

    final promptMap =
        json['prompt'] as Map<String, dynamic>? ??
        _derivePromptFromStimulus(json['stimulus']);
    final promptText = (json['prompt_text']?.toString() ?? '').trim().isNotEmpty
        ? json['prompt_text']?.toString()
        : _derivePromptTextFromStimulus(json['stimulus']);

    return PilotExerciseItem(
      id: json['id']?.toString() ?? '',
      templateId: templateId,
      variantId: resolvedVariant,
      exerciseType: resolvedVariant,
      conceptId: _parseConceptId(json),
      unitId: json['unit_id']?.toString() ?? metaJson['unit_id']?.toString(),
      level: json['level'] ?? 1,
      skill:
          json['skill']?.toString() ?? _defaultSkillForVariant(resolvedVariant),
      constraints: PilotConstraints.fromJson(
        json['constraints'] as Map<String, dynamic>? ?? const {},
      ),
      attemptsAllowed: json['attempts_allowed'] ?? 3,
      timeLimitMs: json['time_limit_ms'] is int
          ? json['time_limit_ms'] as int
          : null,
      difficultyLevel: json['difficulty_level'] ?? (json['level'] ?? 1),
      requiredAssets: PilotRequiredAssets.fromJson(
        json['required_assets'] as Map<String, dynamic>? ?? const {},
      ),
      promptText: promptText,
      prompt: PilotPrompt.fromJson(promptMap),
      choices: choices,
      answerIndex: answerIndex,
      options: options,
      correctOptionId: correctOptionId,
      meta: PilotMeta.fromJson(metaJson),
      why: whyRaw != null ? PilotWhy.fromJson(whyRaw) : null,
      audioUrl: json['audio_url']?.toString(),
      choiceType: json['choice_type']?.toString(),
      payload: payload,
      reading: readingRaw is Map<String, dynamic>
          ? PilotReading.fromJson(readingRaw)
          : null,
      questions: questionsJson
          .map((q) => PilotQuestion.fromJson(q as Map<String, dynamic>))
          .toList(),
    );
  }

  static String _defaultVariantForTemplate(String templateId) {
    switch (templateId) {
      case 'select_one':
        return 'meaning_select';
      case 'arrange':
        return 'order_sentence';
      case 'match_pairs':
        return 'meaning_match';
      case 'passage_qa':
        return 'reading_micro';
      case 'speak':
        return 'speak_read_aloud';
      default:
        return '';
    }
  }

  static String _defaultSkillForVariant(String variantId) {
    switch (variantId) {
      case 'audio_select':
      case 'dictation_select':
      case 'listen_write':
        return 'listening';
      case 'order_sentence':
      case 'character_select':
      case 'pinyin_select':
        return 'characters';
      case 'reading_micro':
      case 'cloze_select':
        return 'reading';
      case 'speak_read_aloud':
      case 'speak_prompted_reply':
      case 'reply_select':
        return 'production';
      case 'meaning_match':
      case 'meaning_select':
      default:
        return 'meaning';
    }
  }

  static List<String> _extractChoices({
    required dynamic choices,
    required List<PilotOption> options,
    required Map<String, dynamic> interaction,
  }) {
    final direct = (choices as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
    if (direct.isNotEmpty) return direct;
    if (options.isNotEmpty) {
      return options.map((o) => o.text).where((e) => e.isNotEmpty).toList();
    }
    final interactionOptions =
        (interaction['options'] as List<dynamic>? ?? const []);
    final extracted = <String>[];
    for (final raw in interactionOptions) {
      if (raw is! Map) continue;
      final option = raw.cast<String, dynamic>();
      final text = _optionText(option);
      if (text.isNotEmpty) {
        extracted.add(text);
      }
    }
    return extracted;
  }

  static int _extractAnswerIndex({
    required dynamic rawAnswerIndex,
    required Map<String, dynamic> interaction,
    required Map<String, dynamic> evaluation,
  }) {
    if (rawAnswerIndex is int && rawAnswerIndex >= 0) return rawAnswerIndex;

    final correctIds =
        (evaluation['correct_option_ids'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
    if (correctIds.isEmpty) return 0;

    final options = (interaction['options'] as List<dynamic>? ?? const []);
    final wanted = correctIds.first;
    for (var i = 0; i < options.length; i++) {
      final raw = options[i];
      if (raw is! Map) continue;
      final option = raw.cast<String, dynamic>();
      if ((option['id']?.toString() ?? '') == wanted) {
        return i;
      }
    }
    return 0;
  }

  static String _optionText(Map<String, dynamic> option) {
    final explicit = (option['text']?.toString() ?? '').trim();
    if (explicit.isNotEmpty) return explicit;
    final label = (option['label']?.toString() ?? '').trim();
    if (label.isNotEmpty) return label;
    final stimulus = (option['stimulus'] as List<dynamic>? ?? const []);
    for (final atom in stimulus) {
      if (atom is! Map) continue;
      final map = atom.cast<String, dynamic>();
      final type = (map['type']?.toString() ?? '').toLowerCase();
      final text = (map['text']?.toString() ?? '').trim();
      if (type == 'text' && text.isNotEmpty) return text;
    }
    return '';
  }

  static Map<String, dynamic> _derivePromptFromStimulus(dynamic rawStimulus) {
    final out = <String, dynamic>{};
    final stimulus = (rawStimulus as List<dynamic>? ?? const []);
    for (final atom in stimulus) {
      if (atom is! Map) continue;
      final map = atom.cast<String, dynamic>();
      final type = (map['type']?.toString() ?? '').toLowerCase();
      final role = (map['role']?.toString() ?? '').toLowerCase();
      final text = (map['text']?.toString() ?? '').trim();
      if (type != 'text' || text.isEmpty) continue;
      if (role == 'hint') {
        out['meaning'] = out['meaning'] ?? text;
      } else {
        out['hanzi'] = out['hanzi'] ?? text;
      }
    }
    return out;
  }

  static String? _derivePromptTextFromStimulus(dynamic rawStimulus) {
    final stimulus = (rawStimulus as List<dynamic>? ?? const []);
    for (final atom in stimulus) {
      if (atom is! Map) continue;
      final map = atom.cast<String, dynamic>();
      final type = (map['type']?.toString() ?? '').toLowerCase();
      final role = (map['role']?.toString() ?? '').toLowerCase();
      final text = (map['text']?.toString() ?? '').trim();
      if (type == 'text' &&
          text.isNotEmpty &&
          (role == 'prompt' || role == 'context')) {
        return text;
      }
    }
    return null;
  }

  static int _parseConceptId(Map<String, dynamic> json) {
    final direct = json['concept_id'];
    final parsedDirect = _coerceConceptId(direct);
    if (parsedDirect != null) return parsedDirect;

    final objective = (json['objective'] as Map<String, dynamic>? ?? const {});
    final conceptIds = (objective['concept_ids'] as List<dynamic>? ?? const []);
    if (conceptIds.isNotEmpty) {
      final parsedObjective = _coerceConceptId(conceptIds.first);
      if (parsedObjective != null) return parsedObjective;
    }
    return 0;
  }

  static int? _coerceConceptId(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    final asString = (raw?.toString() ?? '').trim();
    if (asString.isEmpty) return null;
    final asInt = int.tryParse(asString);
    if (asInt != null) return asInt;
    return _stableInt(asString);
  }

  static int _stableInt(String value) {
    // FNV-1a 32-bit (stable across runs).
    var hash = 0x811c9dc5;
    for (final rune in value.runes) {
      hash ^= rune;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }
}

class PilotPrompt {
  final String? hanzi;
  final String? pinyin;
  final String? meaning;

  const PilotPrompt({this.hanzi, this.pinyin, this.meaning});

  factory PilotPrompt.fromJson(Map<String, dynamic> json) {
    String? pick(List<String> keys) {
      for (final key in keys) {
        final raw = json[key];
        if (raw == null) continue;
        final value = raw.toString().trim();
        if (value.isNotEmpty) return value;
      }
      return null;
    }

    return PilotPrompt(
      hanzi: pick(const ['hanzi', 'text', 'term', 'label', 'title']),
      pinyin: pick(const ['pinyin', 'pronunciation', 'phonetic']),
      meaning: pick(const [
        'meaning',
        'translation',
        'definition',
        'explanation',
      ]),
    );
  }
}

class PilotMeta {
  final int hskLevel;
  final String? unitId;
  final List<String> tags;

  PilotMeta({required this.hskLevel, this.unitId, required this.tags});

  factory PilotMeta.fromJson(Map<String, dynamic> json) {
    return PilotMeta(
      hskLevel: json['hsk_level'] ?? 0,
      unitId: json['unit_id']?.toString(),
      tags: (json['tags'] as List<dynamic>? ?? []).cast<String>(),
    );
  }
}

class PilotWhy {
  final List<String> reasons;
  final List<String> reasonCodes;
  final PilotWhySignals signals;

  PilotWhy({
    required this.reasons,
    this.reasonCodes = const [],
    required this.signals,
  });

  factory PilotWhy.fromJson(Map<String, dynamic> json) {
    final reasons = (json['reasons'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();
    final codes = (json['reason_codes'] as List<dynamic>?)
        ?.map((e) => e.toString())
        .toList();
    if (reasons == null) {
      final legacy = [
        json['reason_word']?.toString(),
        json['reason_exercise']?.toString(),
        json['next_step']?.toString(),
        json['exam_skill']?.toString(),
      ].whereType<String>().where((e) => e.isNotEmpty).toList();
      return PilotWhy(
        reasons: legacy,
        reasonCodes: codes ?? const [],
        signals: PilotWhySignals.fromJson(
          json['signals'] as Map<String, dynamic>? ?? const {},
        ),
      );
    }
    return PilotWhy(
      reasons: reasons,
      reasonCodes: codes ?? const [],
      signals: PilotWhySignals.fromJson(
        json['signals'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class PilotWhySignals {
  final double? accuracy;
  final int? latencyMs;
  final int? mistakeCount;
  final String? skillTarget;
  final String? wordStage;
  final int? dueInMs;

  PilotWhySignals({
    this.accuracy,
    this.latencyMs,
    this.mistakeCount,
    this.skillTarget,
    this.wordStage,
    this.dueInMs,
  });

  factory PilotWhySignals.fromJson(Map<String, dynamic> json) {
    return PilotWhySignals(
      accuracy: (json['accuracy'] is num)
          ? (json['accuracy'] as num).toDouble()
          : null,
      latencyMs: json['latencyMs'] is int ? json['latencyMs'] as int : null,
      mistakeCount: json['mistakeCount'] is int
          ? json['mistakeCount'] as int
          : null,
      skillTarget: json['skill_target']?.toString(),
      wordStage: json['word_stage']?.toString(),
      dueInMs: json['due_in_ms'] is int ? json['due_in_ms'] as int : null,
    );
  }
}

class PilotConstraints {
  final int? timedSec;
  final String? retryPolicy;

  PilotConstraints({this.timedSec, this.retryPolicy});

  factory PilotConstraints.fromJson(Map<String, dynamic> json) {
    return PilotConstraints(
      timedSec: json['timedSec'] is int ? json['timedSec'] as int : null,
      retryPolicy: json['retryPolicy']?.toString(),
    );
  }
}

class PilotRequiredAssets {
  final bool audio;
  final bool image;

  const PilotRequiredAssets({required this.audio, required this.image});

  factory PilotRequiredAssets.fromJson(Map<String, dynamic> json) {
    return PilotRequiredAssets(
      audio: json['audio'] == true,
      image: json['image'] == true,
    );
  }
}

class PilotReading {
  final String titleZh;
  final String titleEn;
  final String storyZh;
  final String storyPinyin;
  final String storyEn;

  PilotReading({
    required this.titleZh,
    required this.titleEn,
    required this.storyZh,
    required this.storyPinyin,
    required this.storyEn,
  });

  factory PilotReading.fromJson(Map<String, dynamic> json) {
    return PilotReading(
      titleZh: json['title_zh']?.toString() ?? '',
      titleEn: json['title_en']?.toString() ?? '',
      storyZh: json['story_zh']?.toString() ?? '',
      storyPinyin: json['story_pinyin']?.toString() ?? '',
      storyEn: json['story_en']?.toString() ?? '',
    );
  }
}

class PilotQuestion {
  final String type;
  final Map<String, dynamic> prompt;
  final List<String> choices;
  final int answerIndex;

  PilotQuestion({
    required this.type,
    required this.prompt,
    required this.choices,
    required this.answerIndex,
  });

  factory PilotQuestion.fromJson(Map<String, dynamic> json) {
    return PilotQuestion(
      type: json['type']?.toString() ?? '',
      prompt: (json['prompt'] as Map<String, dynamic>? ?? const {}),
      choices: (json['choices'] as List<dynamic>? ?? []).cast<String>(),
      answerIndex: json['answer_index'] ?? 0,
    );
  }
}

class PilotOption {
  final String id;
  final String text;

  PilotOption({required this.id, required this.text});

  factory PilotOption.fromJson(Map<String, dynamic> json) {
    return PilotOption(
      id: json['id']?.toString() ?? '',
      text: json['text']?.toString() ?? '',
    );
  }
}
