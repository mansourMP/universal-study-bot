import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/tutor/models/ai_exercise_schema.dart';

class AiExercisePackBridge {
  const AiExercisePackBridge._();

  static PilotExercisePack toPilotPack(AiExerciseSchema schema) {
    return PilotExercisePack(
      schemaVersion: schema.schemaVersion,
      generatedAt: schema.generatedAt,
      items: List<PilotExerciseItem>.generate(schema.items.length, (index) {
        return _toPilotItem(schema.items[index], index);
      }, growable: false),
    );
  }

  static PilotExerciseItem _toPilotItem(AiExerciseItem item, int index) {
    final normalizedType = item.exerciseType.trim();
    final effectiveType = normalizedType.isEmpty
        ? 'meaning_select'
        : normalizedType;
    final choices = item.choices;
    final safeAnswerIndex = (() {
      if (choices.isEmpty) return 0;
      final idx = item.answerIndex ?? 0;
      if (idx < 0) return 0;
      if (idx >= choices.length) return choices.length - 1;
      return idx;
    })();

    final prompt = _promptFrom(item);
    final payload = <String, dynamic>{
      ...item.payload,
      if (item.promptText.trim().isNotEmpty) 'prompt_text': item.promptText,
      if (item.audioUrl != null && item.audioUrl!.trim().isNotEmpty)
        'audio_url': item.audioUrl,
      if (item.imageUrl != null && item.imageUrl!.trim().isNotEmpty)
        'image_url': item.imageUrl,
    };

    final options = choices
        .asMap()
        .entries
        .map((entry) => PilotOption(id: 'opt_${entry.key}', text: entry.value))
        .toList(growable: false);

    return PilotExerciseItem(
      id: item.id,
      templateId: effectiveType,
      variantId: effectiveType,
      exerciseType: effectiveType,
      conceptId:
          _coerceInt(item.meta['concept_id'] ?? item.meta['conceptId']) ??
          (index + 1),
      unitId: item.unitId,
      level: item.level,
      skill: item.skill.trim().isEmpty
          ? _defaultSkillForType(effectiveType)
          : item.skill,
      constraints: PilotConstraints(
        timedSec: _coerceInt(item.meta['timed_sec']),
        retryPolicy: item.meta['retry_policy']?.toString(),
      ),
      attemptsAllowed: _coerceInt(item.meta['attempts_allowed']) ?? 3,
      timeLimitMs: _coerceInt(item.meta['time_limit_ms']),
      difficultyLevel: _coerceInt(item.meta['difficulty_level']) ?? item.level,
      requiredAssets: PilotRequiredAssets(
        audio: item.audioUrl?.trim().isNotEmpty == true,
        image: item.imageUrl?.trim().isNotEmpty == true,
      ),
      promptText: item.promptText,
      prompt: prompt,
      choices: choices,
      answerIndex: safeAnswerIndex,
      options: options,
      correctOptionId: choices.isEmpty
          ? null
          : 'opt_${safeAnswerIndex.clamp(0, choices.length - 1)}',
      meta: PilotMeta(
        hskLevel: _coerceInt(item.meta['hsk_level']) ?? item.level,
        unitId: item.unitId,
        tags: _coerceStringList(item.meta['tags']),
      ),
      why: null,
      audioUrl: item.audioUrl,
      choiceType: item.meta['choice_type']?.toString(),
      payload: payload,
      reading: _readingFrom(item.payload),
      questions: _questionsFrom(item.payload),
    );
  }

  static PilotPrompt _promptFrom(AiExerciseItem item) {
    final promptRaw = item.payload['prompt'];
    if (promptRaw is Map<String, dynamic>) {
      return PilotPrompt.fromJson(promptRaw);
    }
    if (promptRaw is Map) {
      return PilotPrompt.fromJson(promptRaw.cast<String, dynamic>());
    }

    final text = item.promptText.trim();
    return PilotPrompt(
      hanzi: text.isEmpty ? null : text,
      pinyin: item.payload['pinyin']?.toString(),
      meaning: item.payload['meaning']?.toString(),
    );
  }

  static PilotReading? _readingFrom(Map<String, dynamic> payload) {
    final readingRaw = payload['reading'];
    if (readingRaw is Map<String, dynamic>) {
      return PilotReading.fromJson(readingRaw);
    }
    if (readingRaw is Map) {
      return PilotReading.fromJson(readingRaw.cast<String, dynamic>());
    }
    return null;
  }

  static List<PilotQuestion> _questionsFrom(Map<String, dynamic> payload) {
    final raw = payload['questions'];
    if (raw is! List) return const <PilotQuestion>[];
    return raw
        .whereType<Map>()
        .map((e) => PilotQuestion.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  static int? _coerceInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  static List<String> _coerceStringList(dynamic value) {
    if (value is! List) return const <String>[];
    return value
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  static String _defaultSkillForType(String exerciseType) {
    switch (exerciseType) {
      case 'audio_select':
      case 'dictation_select':
      case 'listen_write':
        return 'listening';
      case 'reading_micro':
      case 'reading_span_select':
      case 'cloze_select':
        return 'reading';
      case 'speak_read_aloud':
      case 'speak_prompted_reply':
      case 'conversation_simulation':
      case 'reply_select':
        return 'production';
      default:
        return 'meaning';
    }
  }
}
