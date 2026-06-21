import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/services/speaking_recorder.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_media.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/multiple_choice_exercise.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/speaking_exercise.dart';
import 'package:dragon_chinese/features/learning_engine/engine/attempt_signal_engine.dart';
import 'package:dragon_chinese/features/learning_engine/models/attempt_signal.dart';
import 'package:dragon_chinese/features/learning_engine/engine/exercise_engine.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_response.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_spec.dart';

class PracticeExerciseUiState {
  final int? selectedIndex;
  final String textAnswer;
  final bool isAnswered;
  final bool showPinyin;
  final int readingQuestionIndex;
  final List<String> orderChunks;
  final List<String> orderAnswer;
  final bool matchReady;
  final bool matchCorrect;
  final bool speakingPermissionGranted;
  final bool speakingIsRecording;
  final SpeakingRecording? speakingRecording;
  final SpeakingRating? speakingRating;
  final double? speakingScore;

  const PracticeExerciseUiState({
    required this.selectedIndex,
    required this.textAnswer,
    required this.isAnswered,
    required this.showPinyin,
    required this.readingQuestionIndex,
    required this.orderChunks,
    required this.orderAnswer,
    required this.matchReady,
    required this.matchCorrect,
    required this.speakingPermissionGranted,
    required this.speakingIsRecording,
    required this.speakingRecording,
    required this.speakingRating,
    required this.speakingScore,
  });
}

class _FlashcardExerciseView extends StatefulWidget {
  final String front;
  final String? pinyin;
  final String? back;

  const _FlashcardExerciseView({
    required this.front,
    required this.pinyin,
    required this.back,
  });

  @override
  State<_FlashcardExerciseView> createState() => _FlashcardExerciseViewState();
}

class _FlashcardExerciseViewState extends State<_FlashcardExerciseView> {
  bool _showBack = false;
  bool _flipFromRight = true;

  void _toggleFlip([TapDownDetails? details]) {
    if (details != null) {
      final box = context.findRenderObject() as RenderBox?;
      final local = details.localPosition;
      final width = box?.size.width ?? 0;
      if (width > 0) {
        _flipFromRight = local.dx >= (width / 2);
      }
    }
    setState(() => _showBack = !_showBack);
  }

  @override
  Widget build(BuildContext context) {
    final front = widget.front;
    final pinyin = widget.pinyin;
    final back = widget.back;
    final viewportHeight = MediaQuery.of(context).size.height;
    final stageHeight = (viewportHeight * 0.5).clamp(320.0, 540.0);
    final charCount = front.runes.length;
    final frontSize = charCount <= 2 ? 36.0 : (charCount <= 6 ? 32.0 : 28.0);
    final hasBack = back != null && back.trim().isNotEmpty;

    return SizedBox(
      height: stageHeight,
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 300, maxWidth: 430),
          child: AspectRatio(
            aspectRatio: 1.02,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: _toggleFlip,
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(
                  begin: 0,
                  end: _showBack && hasBack ? 1 : 0,
                ),
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeInOutCubic,
                builder: (context, value, _) {
                  final angle = value * math.pi;
                  final isPastHalf = angle > (math.pi / 2);
                  final showFrontFace = !isPastHalf;
                  final adjusted = showFrontFace ? angle : angle - math.pi;
                  final signedAngle = (_flipFromRight ? 1.0 : -1.0) * adjusted;

                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, 0.0018)
                      ..rotateY(signedAngle),
                    child: _flashcardFace(
                      front: front,
                      pinyin: pinyin,
                      back: hasBack ? back.trim() : null,
                      frontSize: frontSize,
                      showFrontFace: showFrontFace || !hasBack,
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _flashcardFace({
    required String front,
    required String? pinyin,
    required String? back,
    required double frontSize,
    required bool showFrontFace,
  }) {
    return Container(
      width: double.infinity,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 26),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0xFFE3E8F1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        children: showFrontFace
            ? [
                Text(
                  front,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: frontSize,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF111827),
                  ),
                ),
                if (pinyin != null && pinyin.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    pinyin.trim(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ],
              ]
            : [
                Text(
                  back ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  front,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
                if (pinyin != null && pinyin.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    pinyin.trim(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ],
      ),
    );
  }
}

class PracticeExerciseCallbacks {
  final ValueChanged<int> onSelectIndex;
  final ValueChanged<String> onTextChanged;
  final VoidCallback onTogglePinyin;
  final ValueChanged<List<String>> onOrderChanged;
  final void Function(bool ready, bool correct) onMatchStatus;
  final VoidCallback onRequestSpeakingPermission;
  final VoidCallback onStartSpeakingRecording;
  final VoidCallback onStopSpeakingRecording;
  final ValueChanged<SpeakingRating> onSetSpeakingRating;

  const PracticeExerciseCallbacks({
    required this.onSelectIndex,
    required this.onTextChanged,
    required this.onTogglePinyin,
    required this.onOrderChanged,
    required this.onMatchStatus,
    required this.onRequestSpeakingPermission,
    required this.onStartSpeakingRecording,
    required this.onStopSpeakingRecording,
    required this.onSetSpeakingRating,
  });
}

typedef _RendererFn =
    Widget Function(
      PilotExerciseItem item,
      PracticeExerciseUiState state,
      PracticeExerciseCallbacks callbacks,
      String? resolvedPromptText,
    );
typedef _CheckFn =
    bool Function(PilotExerciseItem item, PracticeExerciseUiState state);
typedef _ValidatorFn =
    bool Function(PilotExerciseItem item, String? promptText);
typedef _InstructionFn =
    String Function(PilotExerciseItem item, String? promptText);
typedef _RevealFn = String Function(PilotExerciseItem item);

enum ExerciseTemplateFamily { selection, sequence, matching, passage, speaking }

class ExerciseTemplateContract {
  final String type;
  final ExerciseTemplateFamily family;
  final List<String> requiredPayloadKeys;
  final List<String> optionalPayloadKeys;
  final String uiTemplate;

  const ExerciseTemplateContract({
    required this.type,
    required this.family,
    required this.requiredPayloadKeys,
    required this.optionalPayloadKeys,
    required this.uiTemplate,
  });
}

class PracticeExerciseEngine {
  static const String engineId = 'omnis.exercise_engine.v1';
  static const Set<String> _temporarilyDisabledTypes = {
    'character_writing',
    'reverse_recall',
  };

  static final GenericExerciseEngine _coreEngine =
      GenericExerciseEngine.defaultEngine();

  static const Map<String, String> _typeAliases = {
    'speaking': 'speak_prompted_reply',
    'dialogue_turn': 'reply_select',
    'passage_select': 'reading_micro',
    'read_select_passage': 'reading_micro',
    'read_and_select_in_passage': 'reading_span_select',
    'sentence_fill': 'cloze_select',
    'fill_blank': 'cloze_select',
    'fill_in_blank': 'cloze_select',
    'sentence_blank_select': 'cloze_select',
    'context_cloze_select': 'cloze_select',
    'passage_blank_select': 'cloze_select',
    'complete_sentence_select': 'cloze_select',
    'phrase_blank_select': 'cloze_select',
    'clause_blank_select': 'cloze_select',
    'sentence_completion_select': 'cloze_select',
    'text_input': 'reverse_recall',
    'short_answer': 'reverse_recall',
    'listening_choose': 'audio_select',
    'listen_and_choose': 'audio_select',
    'listen_write': 'listen_write',
    'listen_and_write': 'listen_write',
    'listening_write': 'listen_write',
    'dictation_input': 'listen_write',
    'single_select': 'meaning_select',
    'multiple_choice': 'meaning_select',
    'mcq': 'meaning_select',
    'sentence_building': 'order_sentence',
    'pair_match': 'meaning_match',
    'conversation_choice': 'conversation_simulation',
    'pronunciation_read_aloud': 'speak_read_aloud',
    'tone_select': 'flashcard',
  };

  static const Set<String> _speakingTypes = {
    'speak_read_aloud',
    'speak_prompted_reply',
  };

  static const Set<String> _audioTypes = {
    'audio_select',
    'dictation_select',
    'listen_write',
  };

  static final Map<String, _RendererFn> _renderers = {
    'flashcard': _renderFlashcard,
    'character_writing': _renderCharacterWriting,
    'true_false': _renderTrueFalse,
    'reverse_recall': _renderReverseRecall,
    'error_correction': _renderErrorCorrection,
    'meaning_select': _renderMeaningSelect,
    'character_select': _renderCharacterSelect,
    'audio_select': _renderAudioSelect,
    'dictation_select': _renderDictationSelect,
    'listen_write': _renderListenWrite,
    'cloze_select': _renderClozeSelect,
    'order_sentence': _renderOrderSentence,
    'meaning_match': _renderMeaningMatch,
    'audio_match': _renderAudioMatch,
    'reading_micro': _renderReadingMicro,
    'reading_span_select': _renderReadingSpanSelect,
    'pinyin_select': _renderPinyinSelect,
    'reply_select': _renderReplySelect,
    'conversation_simulation': _renderConversationSimulation,
    'speak_read_aloud': _renderSpeakReadAloud,
    'speak_prompted_reply': _renderSpeakPromptedReply,
  };

  static final Map<String, _CheckFn> _correctChecks = {
    'reading_micro': _isReadingCorrect,
    'order_sentence': _isOrderSentenceCorrect,
    'meaning_match': _isMeaningMatchCorrect,
    'audio_match': _isMeaningMatchCorrect,
  };

  static final Map<String, _CheckFn> _readyChecks = {
    'order_sentence': _isOrderSentenceReady,
    'meaning_match': _isMeaningMatchReady,
    'audio_match': _isMeaningMatchReady,
  };

  static final Map<String, _ValidatorFn> _validators = {
    'flashcard': _validateFlashcard,
    'character_writing': _validateCharacterWriting,
    'true_false': _validateTrueFalse,
    'reverse_recall': _validateReverseRecall,
    'error_correction': _validateErrorCorrection,
    'listen_write': _validateListenWrite,
    'cloze_select': _validateClozeSelect,
    'reading_micro': _validateReadingMicro,
    'reading_span_select': _validateReadingSpanSelect,
    'order_sentence': _validateOrderSentence,
    'meaning_match': _validateMeaningMatch,
    'audio_match': _validateAudioMatch,
    'conversation_simulation': _validateConversationSimulation,
    'speak_read_aloud': _validateSpeakReadAloud,
    'speak_prompted_reply': _validateSpeakPromptedReply,
  };

  static final Map<String, _InstructionFn> _instructions = {
    'flashcard': (_, __) => 'Study the card',
    'character_writing': (_, __) => 'Write the character',
    'true_false': (_, __) => 'True or False',
    'reverse_recall': (_, __) => 'Type the answer',
    'error_correction': (_, __) => 'Correct the sentence',
    'meaning_select': (_, __) => 'Choose the meaning',
    'character_select': (_, __) => 'Choose the characters',
    'pinyin_select': (_, __) => 'Choose the correct pinyin',
    'reply_select': (_, __) => 'Choose the best reply',
    'conversation_simulation': (_, __) => 'Choose the best next reply',
    'audio_select': (item, __) => item.choiceType == 'meaning'
        ? 'Choose the meaning'
        : 'Choose the characters',
    'dictation_select': (_, text) =>
        text ?? 'Listen and choose the correct sentence',
    'listen_write': (_, text) => text ?? 'Listen and write',
    'cloze_select': (_, __) => 'Complete the sentence',
    'order_sentence': (_, __) => 'Order the sentence',
    'meaning_match': (_, __) => 'Match the pairs',
    'audio_match': (_, __) => 'Match audio to words',
    'reading_micro': (_, __) => 'Read the passage and answer',
    'reading_span_select': (_, __) => 'Read and select the answer',
    'speak_read_aloud': (_, __) => 'Read aloud',
    'speak_prompted_reply': (_, __) => 'Respond aloud',
  };

  static final Map<String, _RevealFn> _reveals = {
    'order_sentence': _revealOrderSentence,
    'meaning_match': _revealMeaningMatch,
  };

  static const Map<String, String> _skillByType = {
    'flashcard': 'meaning',
    'character_writing': 'characters',
    'true_false': 'reading',
    'reverse_recall': 'production',
    'error_correction': 'production',
    'meaning_select': 'meaning',
    'meaning_match': 'meaning',
    'audio_match': 'listening',
    'character_select': 'characters',
    'order_sentence': 'characters',
    'pinyin_select': 'pinyin',
    'dictation_select': 'pinyin',
    'listen_write': 'listening',
    'audio_select': 'listening',
    'cloze_select': 'reading',
    'reading_micro': 'reading',
    'reading_span_select': 'reading',
    'reply_select': 'production',
    'conversation_simulation': 'production',
    'speak_read_aloud': 'production',
    'speak_prompted_reply': 'production',
  };

  static const Map<String, String> _masteryBySkill = {
    'characters': 'character',
    'listening': 'listening',
    'pinyin': 'listening',
    'reading': 'reading',
    'production': 'production',
    'meaning': 'meaning',
  };

  static const Map<String, ExerciseTemplateContract> _contracts = {
    'flashcard': ExerciseTemplateContract(
      type: 'flashcard',
      family: ExerciseTemplateFamily.selection,
      requiredPayloadKeys: [],
      optionalPayloadKeys: ['front', 'back', 'pinyin', 'prompt', 'why'],
      uiTemplate: 'flashcard_view',
    ),
    'character_writing': ExerciseTemplateContract(
      type: 'character_writing',
      family: ExerciseTemplateFamily.sequence,
      requiredPayloadKeys: [],
      optionalPayloadKeys: [
        'target_character',
        'hanzi',
        'pinyin',
        'meaning',
        'prompt',
        'why',
      ],
      uiTemplate: 'character_writing_grid',
    ),
    'true_false': ExerciseTemplateContract(
      type: 'true_false',
      family: ExerciseTemplateFamily.selection,
      requiredPayloadKeys: [],
      optionalPayloadKeys: [
        'statement',
        'prompt_text',
        'choices',
        'answer',
        'answer_index',
        'why',
      ],
      uiTemplate: 'true_false_choice',
    ),
    'reverse_recall': ExerciseTemplateContract(
      type: 'reverse_recall',
      family: ExerciseTemplateFamily.selection,
      requiredPayloadKeys: [],
      optionalPayloadKeys: [
        'prompt',
        'question',
        'answer',
        'accepted_answers',
        'sample_answers',
        'why',
      ],
      uiTemplate: 'text_recall_input',
    ),
    'error_correction': ExerciseTemplateContract(
      type: 'error_correction',
      family: ExerciseTemplateFamily.selection,
      requiredPayloadKeys: [],
      optionalPayloadKeys: [
        'sentence',
        'incorrect_sentence',
        'question',
        'prompt',
        'answer',
        'accepted_answers',
        'sample_answers',
        'correction',
        'corrected_sentence',
        'why',
      ],
      uiTemplate: 'error_correction_input',
    ),
    'meaning_select': ExerciseTemplateContract(
      type: 'meaning_select',
      family: ExerciseTemplateFamily.selection,
      requiredPayloadKeys: ['choices'],
      optionalPayloadKeys: ['prompt', 'why'],
      uiTemplate: 'multiple_choice',
    ),
    'character_select': ExerciseTemplateContract(
      type: 'character_select',
      family: ExerciseTemplateFamily.selection,
      requiredPayloadKeys: ['choices'],
      optionalPayloadKeys: ['prompt', 'why'],
      uiTemplate: 'multiple_choice',
    ),
    'pinyin_select': ExerciseTemplateContract(
      type: 'pinyin_select',
      family: ExerciseTemplateFamily.selection,
      requiredPayloadKeys: ['choices'],
      optionalPayloadKeys: ['prompt', 'why'],
      uiTemplate: 'multiple_choice',
    ),
    'audio_select': ExerciseTemplateContract(
      type: 'audio_select',
      family: ExerciseTemplateFamily.selection,
      requiredPayloadKeys: ['choices'],
      optionalPayloadKeys: ['audio_url', 'audio', 'prompt', 'why'],
      uiTemplate: 'audio_choice',
    ),
    'dictation_select': ExerciseTemplateContract(
      type: 'dictation_select',
      family: ExerciseTemplateFamily.selection,
      requiredPayloadKeys: ['choices'],
      optionalPayloadKeys: ['audio_url', 'audio', 'prompt_text', 'why'],
      uiTemplate: 'audio_choice',
    ),
    'listen_write': ExerciseTemplateContract(
      type: 'listen_write',
      family: ExerciseTemplateFamily.selection,
      requiredPayloadKeys: [],
      optionalPayloadKeys: [
        'audio_url',
        'audio',
        'prompt_text',
        'question',
        'answer',
        'accepted_answers',
        'transcript',
        'sample_answers',
        'why',
      ],
      uiTemplate: 'audio_text_input',
    ),
    'cloze_select': ExerciseTemplateContract(
      type: 'cloze_select',
      family: ExerciseTemplateFamily.selection,
      requiredPayloadKeys: ['sentence'],
      optionalPayloadKeys: [
        'choices',
        'answer',
        'accepted_answers',
        'input_mode',
        'response_mode',
        'blank_mode',
        'choice_mode',
        'variant',
        'prompt',
        'context',
        'context_passage',
        'passage_context',
        'paragraph',
        'max_context_words',
        'why',
      ],
      uiTemplate: 'cloze_choice_or_input',
    ),
    'reply_select': ExerciseTemplateContract(
      type: 'reply_select',
      family: ExerciseTemplateFamily.selection,
      requiredPayloadKeys: ['choices'],
      optionalPayloadKeys: ['prompt', 'why'],
      uiTemplate: 'reply_choice',
    ),
    'conversation_simulation': ExerciseTemplateContract(
      type: 'conversation_simulation',
      family: ExerciseTemplateFamily.selection,
      requiredPayloadKeys: ['choices'],
      optionalPayloadKeys: [
        'scenario',
        'context',
        'question',
        'speaker_a',
        'speaker_a_zh',
        'prompt',
        'answer',
        'answer_index',
        'why',
      ],
      uiTemplate: 'conversation_choice',
    ),
    'order_sentence': ExerciseTemplateContract(
      type: 'order_sentence',
      family: ExerciseTemplateFamily.sequence,
      requiredPayloadKeys: [],
      optionalPayloadKeys: ['chunks', 'tokens', 'parts', 'answer', 'why'],
      uiTemplate: 'token_sequence',
    ),
    'meaning_match': ExerciseTemplateContract(
      type: 'meaning_match',
      family: ExerciseTemplateFamily.matching,
      requiredPayloadKeys: ['left', 'right'],
      optionalPayloadKeys: ['mapping', 'why'],
      uiTemplate: 'pair_matching',
    ),
    'audio_match': ExerciseTemplateContract(
      type: 'audio_match',
      family: ExerciseTemplateFamily.matching,
      requiredPayloadKeys: ['right'],
      optionalPayloadKeys: [
        'left',
        'left_audio_urls',
        'audio_urls',
        'mapping',
        'why',
      ],
      uiTemplate: 'audio_pair_matching',
    ),
    'reading_micro': ExerciseTemplateContract(
      type: 'reading_micro',
      family: ExerciseTemplateFamily.passage,
      requiredPayloadKeys: ['reading', 'questions'],
      optionalPayloadKeys: ['why'],
      uiTemplate: 'passage_qa',
    ),
    'reading_span_select': ExerciseTemplateContract(
      type: 'reading_span_select',
      family: ExerciseTemplateFamily.passage,
      requiredPayloadKeys: ['passage'],
      optionalPayloadKeys: [
        'question',
        'choices',
        'answer',
        'answer_index',
        'why',
      ],
      uiTemplate: 'passage_select',
    ),
    'speak_read_aloud': ExerciseTemplateContract(
      type: 'speak_read_aloud',
      family: ExerciseTemplateFamily.speaking,
      requiredPayloadKeys: ['sample_answers'],
      optionalPayloadKeys: ['prompt', 'why'],
      uiTemplate: 'speak_read_aloud',
    ),
    'speak_prompted_reply': ExerciseTemplateContract(
      type: 'speak_prompted_reply',
      family: ExerciseTemplateFamily.speaking,
      requiredPayloadKeys: ['sample_answers'],
      optionalPayloadKeys: ['prompt', 'why'],
      uiTemplate: 'speak_prompted_reply',
    ),
  };

  static const Set<String> _coreDelegatedTypes = {
    'meaning_select',
    'order_sentence',
    'reply_select',
    'cloze_select',
    'reading_micro',
    'reading_span_select',
  };

  static String normalizeType(String exerciseType) {
    return _typeAliases[exerciseType] ?? exerciseType;
  }

  static ExerciseTemplateContract? contractFor(String exerciseType) {
    final normalizedType = normalizeType(exerciseType);
    return _contracts[normalizedType];
  }

  static bool isKnownType(String exerciseType) {
    return contractFor(exerciseType) != null;
  }

  static bool isTemporarilyDisabledType(String exerciseType) {
    final normalizedType = normalizeType(exerciseType);
    return _temporarilyDisabledTypes.contains(normalizedType);
  }

  static bool isSessionEnabledType(String exerciseType) {
    return isKnownType(exerciseType) &&
        !isTemporarilyDisabledType(exerciseType);
  }

  static bool supportsHeaderPinyinToggle(PilotExerciseItem item) {
    final exerciseType = normalizeType(item.exerciseType);
    switch (exerciseType) {
      case 'meaning_select':
      case 'character_select':
        return true;
      default:
        return false;
    }
  }

  static List<String> temporarilyDisabledTypes() {
    return _temporarilyDisabledTypes.toList(growable: false);
  }

  static List<String> supportedTypes() {
    return _contracts.keys.toList(growable: false);
  }

  static bool _isCoreDelegatedType(String exerciseType) {
    return _coreDelegatedTypes.contains(exerciseType) &&
        _coreEngine.supports(exerciseType);
  }

  static ExerciseSpec? _coreSpecFor(
    PilotExerciseItem item, {
    String? resolvedPromptText,
    PracticeExerciseUiState? state,
  }) {
    final exerciseType = normalizeType(item.exerciseType);
    if (!_isCoreDelegatedType(exerciseType)) return null;

    final promptText = (resolvedPromptText?.trim().isNotEmpty == true)
        ? resolvedPromptText!.trim()
        : (_promptFront(item) ?? _promptMeaning(item) ?? '');

    final payload = Map<String, dynamic>.from(item.payload);

    switch (exerciseType) {
      case 'meaning_select':
      case 'reply_select':
        return ExerciseSpec(
          exerciseId: item.id,
          subjectId: 'language.zh',
          templateId: exerciseType,
          promptText: promptText,
          choices: item.choices,
          answerIndex: item.answerIndex,
          payload: payload,
        );
      case 'order_sentence':
        final payloadChunks = _payloadTokenChunks(item);
        final answerTokens = state?.orderAnswer ?? const <String>[];
        return ExerciseSpec(
          exerciseId: item.id,
          subjectId: 'language.zh',
          templateId: exerciseType,
          promptText: promptText,
          choices: payloadChunks,
          answerTokens: answerTokens.isNotEmpty ? answerTokens : payloadChunks,
          payload: payload,
        );
      case 'cloze_select':
        final sentence =
            _payloadText(item.payload, const [
              'sentence',
              'text',
              'stem',
              'prompt',
              'passage',
            ]) ??
            promptText;
        return ExerciseSpec(
          exerciseId: item.id,
          subjectId: 'language.zh',
          templateId: exerciseType,
          promptText: sentence,
          choices: item.choices,
          answerIndex: item.answerIndex,
          payload: payload,
        );
      case 'reading_micro':
        final reading = item.reading;
        payload['reading_title_zh'] = reading?.titleZh ?? '';
        payload['reading_title_en'] = reading?.titleEn ?? '';
        payload['reading_story_zh'] = reading?.storyZh ?? '';
        payload['reading_story_en'] = reading?.storyEn ?? '';
        payload['questions'] = item.questions
            .map(
              (q) => {
                'type': q.type,
                'prompt': q.prompt,
                'choices': q.choices,
                'answer_index': q.answerIndex,
              },
            )
            .toList(growable: false);
        return ExerciseSpec(
          exerciseId: item.id,
          subjectId: 'language.zh',
          templateId: exerciseType,
          promptText: promptText,
          payload: payload,
        );
      case 'reading_span_select':
        final passage =
            _payloadText(item.payload, const [
              'passage',
              'text',
              'reading',
              'content',
            ]) ??
            '';
        payload['passage'] = passage;
        return ExerciseSpec(
          exerciseId: item.id,
          subjectId: 'language.zh',
          templateId: exerciseType,
          promptText: promptText,
          choices: item.choices,
          answerIndex: item.answerIndex,
          payload: payload,
        );
      default:
        return null;
    }
  }

  static ExerciseResponse? _coreResponseFor(
    PilotExerciseItem item,
    String exerciseType,
    PracticeExerciseUiState state,
  ) {
    switch (exerciseType) {
      case 'meaning_select':
      case 'reply_select':
        return ExerciseResponse.selection(selectedIndex: state.selectedIndex);
      case 'order_sentence':
        return ExerciseResponse.ordering(orderedTokens: state.orderChunks);
      case 'cloze_select':
        if (_isClozeTextMode(item)) {
          return ExerciseResponse.text(typedText: state.textAnswer);
        }
        return ExerciseResponse.selection(selectedIndex: state.selectedIndex);
      case 'reading_micro':
        return ExerciseResponse(
          selectedIndex: state.selectedIndex,
          metadata: {'question_index': state.readingQuestionIndex},
        );
      case 'reading_span_select':
        return ExerciseResponse.selection(selectedIndex: state.selectedIndex);
      default:
        return null;
    }
  }

  static bool? _coreIsCorrect(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
  ) {
    final exerciseType = normalizeType(item.exerciseType);
    if (!_isCoreDelegatedType(exerciseType)) return null;
    final spec = _coreSpecFor(item, state: state);
    final response = _coreResponseFor(item, exerciseType, state);
    if (spec == null || response == null) return null;
    final evaluation = _coreEngine.evaluate(spec, response);
    return evaluation?.isCorrect;
  }

  static bool? _coreIsReady(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
  ) {
    final exerciseType = normalizeType(item.exerciseType);
    if (!_isCoreDelegatedType(exerciseType)) return null;
    final spec = _coreSpecFor(item, state: state);
    final response = _coreResponseFor(item, exerciseType, state);
    if (spec == null || response == null) return null;
    final evaluation = _coreEngine.evaluate(spec, response);
    return evaluation?.isReady;
  }

  static List<String>? _coreValidationIssuesFor(
    PilotExerciseItem item,
    String? resolvedPromptText,
  ) {
    final exerciseType = normalizeType(item.exerciseType);
    if (!_isCoreDelegatedType(exerciseType)) return null;
    final spec = _coreSpecFor(item, resolvedPromptText: resolvedPromptText);
    if (spec == null) return const ['core_spec_build_failed'];
    return _coreEngine.validate(spec);
  }

  static String? _coreInstructionFor(
    PilotExerciseItem item,
    String? resolvedPromptText,
  ) {
    final exerciseType = normalizeType(item.exerciseType);
    if (!_isCoreDelegatedType(exerciseType)) return null;
    final spec = _coreSpecFor(item, resolvedPromptText: resolvedPromptText);
    if (spec == null) return null;
    return _coreEngine.instructionFor(spec);
  }

  static List<String> contractIssuesFor({
    required PilotExerciseItem item,
    String? resolvedPromptText,
  }) {
    final exerciseType = normalizeType(item.exerciseType);
    final coreIssues = _coreValidationIssuesFor(item, resolvedPromptText);
    if (coreIssues != null) return coreIssues;
    final contract = _contracts[exerciseType];
    if (contract == null) return const ['unknown_exercise_type'];

    final issues = <String>[];
    final missingRequired = _missingRequiredForContract(item, contract);
    if (missingRequired.isNotEmpty) {
      issues.add('missing_required: ${missingRequired.join(', ')}');
    }
    issues.addAll(
      _structuralIssuesForType(exerciseType, item, resolvedPromptText),
    );
    return issues;
  }

  static bool isSpeaking(PilotExerciseItem item) {
    final exerciseType = normalizeType(item.exerciseType);
    return _speakingTypes.contains(exerciseType);
  }

  static bool isCorrect({
    required PilotExerciseItem item,
    required PracticeExerciseUiState state,
  }) {
    final exerciseType = normalizeType(item.exerciseType);
    final coreCorrect = _coreIsCorrect(item, state);
    if (coreCorrect != null) return coreCorrect;
    if (exerciseType == 'flashcard') return true;
    if (exerciseType == 'character_writing') return true;
    if (exerciseType == 'reverse_recall') {
      return _isReverseRecallCorrect(item, state.textAnswer);
    }
    if (exerciseType == 'error_correction') {
      if (_isErrorCorrectionTokenMode(item)) {
        return _isErrorCorrectionOrderCorrect(item, state.orderChunks);
      }
      return _isErrorCorrectionCorrect(item, state.textAnswer);
    }
    if (exerciseType == 'listen_write') {
      return _isListenWriteCorrect(item, state.textAnswer);
    }
    if (exerciseType == 'cloze_select' && _isClozeTextMode(item)) {
      return _isClozeTextCorrect(item, state.textAnswer);
    }
    final check = _correctChecks[exerciseType];
    if (check != null) return check(item, state);
    return state.selectedIndex == item.answerIndex;
  }

  static bool isReady({
    required PilotExerciseItem item,
    required PracticeExerciseUiState state,
  }) {
    final exerciseType = normalizeType(item.exerciseType);
    final coreReady = _coreIsReady(item, state);
    if (coreReady != null) return coreReady;
    if (exerciseType == 'flashcard') return true;
    if (exerciseType == 'character_writing') return true;
    if (exerciseType == 'reverse_recall') {
      return state.textAnswer.trim().isNotEmpty;
    }
    if (exerciseType == 'error_correction') {
      if (_isErrorCorrectionTokenMode(item)) {
        final expectedCount = _errorCorrectionIncorrectTokens(item).length;
        if (expectedCount > 0) {
          return state.orderChunks.length >= expectedCount;
        }
        return state.orderChunks.isNotEmpty;
      }
      return state.textAnswer.trim().isNotEmpty;
    }
    if (exerciseType == 'listen_write') {
      return state.textAnswer.trim().isNotEmpty;
    }
    if (isSpeaking(item)) return state.speakingRating != null;
    if (exerciseType == 'cloze_select' && _isClozeTextMode(item)) {
      return state.textAnswer.trim().isNotEmpty;
    }
    final check = _readyChecks[exerciseType];
    if (check != null) return check(item, state);
    return state.selectedIndex != null;
  }

  static bool isItemValid({
    required PilotExerciseItem item,
    String? resolvedPromptText,
  }) {
    final exerciseType = normalizeType(item.exerciseType);
    final coreIssues = _coreValidationIssuesFor(item, resolvedPromptText);
    if (coreIssues != null) return coreIssues.isEmpty;
    final contract = _contracts[exerciseType];
    if (contract == null) return false;
    final validator = _validators[exerciseType];
    final passesBase = validator != null
        ? validator(item, resolvedPromptText)
        : item.choices.isNotEmpty;
    if (!passesBase) return false;

    final missingRequired = _missingRequiredForContract(item, contract);
    if (missingRequired.isNotEmpty) return false;
    final structuralIssues = _structuralIssuesForType(
      exerciseType,
      item,
      resolvedPromptText,
    );
    return structuralIssues.isEmpty;
  }

  static List<String> _missingRequiredForContract(
    PilotExerciseItem item,
    ExerciseTemplateContract contract,
  ) {
    final missing = <String>[];
    for (final key in contract.requiredPayloadKeys) {
      var has = false;
      switch (key) {
        case 'choices':
          has = item.choices.isNotEmpty;
          break;
        case 'questions':
          has = item.questions.isNotEmpty;
          break;
        case 'reading':
          has = item.reading != null;
          break;
        default:
          final value = item.payload[key];
          if (value is String) {
            has = value.trim().isNotEmpty;
          } else if (value is List) {
            has = value.isNotEmpty;
          } else if (value is Map) {
            has = value.isNotEmpty;
          } else {
            has = value != null;
          }
      }
      if (!has) missing.add(key);
    }
    return missing;
  }

  static List<String> _structuralIssuesForType(
    String exerciseType,
    PilotExerciseItem item,
    String? resolvedPromptText,
  ) {
    final issues = <String>[];
    if (item.choices.isNotEmpty &&
        (item.answerIndex < 0 || item.answerIndex >= item.choices.length)) {
      issues.add('answer_index_out_of_range');
    }
    switch (exerciseType) {
      case 'meaning_match':
        final left = (item.payload['left'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(growable: false);
        final right = (item.payload['right'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(growable: false);
        final mapping = (item.payload['mapping'] as List<dynamic>? ?? [])
            .whereType<int>()
            .toList(growable: false);
        if (left.length != right.length) {
          issues.add('match_side_length_mismatch');
        }
        issues.addAll(
          _pairMappingIssues(
            leftCount: left.length,
            rightCount: right.length,
            mapping: mapping,
          ),
        );
        break;
      case 'audio_match':
        final right = (item.payload['right'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(growable: false);
        final left = (item.payload['left'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList(growable: false);
        final leftAudio =
            (item.payload['left_audio_urls'] as List<dynamic>? ??
                    item.payload['audio_urls'] as List<dynamic>? ??
                    const [])
                .map((e) => e.toString().trim())
                .toList(growable: false);
        final mapping = (item.payload['mapping'] as List<dynamic>? ?? [])
            .whereType<int>()
            .toList(growable: false);

        final hasAnyAudioUrl = leftAudio.any((e) => e.isNotEmpty);
        if (left.isEmpty && !hasAnyAudioUrl) {
          issues.add('audio_source_missing');
        }
        if (left.isNotEmpty && left.length != right.length) {
          issues.add('audio_match_side_length_mismatch');
        }
        if (leftAudio.isNotEmpty &&
            right.isNotEmpty &&
            leftAudio.length < right.length) {
          issues.add('audio_url_count_lt_right_count');
        }
        final leftCountForMapping = left.isNotEmpty
            ? left.length
            : right.length;
        issues.addAll(
          _pairMappingIssues(
            leftCount: leftCountForMapping,
            rightCount: right.length,
            mapping: mapping,
          ),
        );
        break;
      case 'reading_micro':
        if (item.questions.isEmpty) {
          issues.add('questions_empty');
        }
        for (var i = 0; i < item.questions.length; i++) {
          final q = item.questions[i];
          if (q.choices.length < 2) {
            issues.add('question_${i + 1}_choices_lt_2');
          }
          if (q.choices.isNotEmpty &&
              (q.answerIndex < 0 || q.answerIndex >= q.choices.length)) {
            issues.add('question_${i + 1}_answer_index_out_of_range');
          }
        }
        break;
      case 'reading_span_select':
        if (item.choices.length < 2) {
          issues.add('choices_lt_2');
        }
        break;
      case 'cloze_select':
        if (!_isClozeTextMode(item) && item.choices.length < 2) {
          issues.add('choices_lt_2_for_select_mode');
        }
        if (_isClozeTextMode(item) && _expectedClozeTextAnswers(item).isEmpty) {
          issues.add('expected_answers_missing_for_text_mode');
        }
        break;
      case 'listen_write':
        if (_expectedListenWriteAnswers(item).isEmpty) {
          issues.add('expected_answers_missing');
        }
        final hasAudio = _audioUrlForItem(item) != null;
        if (!hasAudio) {
          issues.add('audio_source_missing');
        }
        break;
      case 'order_sentence':
        if (_payloadTokenChunks(item).isEmpty) {
          issues.add('chunks_missing');
        }
        break;
      case 'true_false':
        if (item.choices.length < 2) {
          issues.add('choices_lt_2');
        }
        break;
      case 'reverse_recall':
        if (_expectedReverseRecallAnswers(item).isEmpty) {
          issues.add('expected_answers_missing');
        }
        break;
      case 'error_correction':
        final hasTokenContract =
            _errorCorrectionIncorrectTokens(item).isNotEmpty &&
            _errorCorrectionAnswerTokens(item).isNotEmpty;
        if (_expectedErrorCorrectionAnswers(item).isEmpty &&
            !hasTokenContract) {
          issues.add('expected_answers_missing');
        }
        break;
      case 'speak_read_aloud':
      case 'speak_prompted_reply':
        if (_speakingSamples(item).isEmpty) {
          issues.add('sample_answers_missing');
        }
        if (exerciseType == 'speak_prompted_reply' &&
            (resolvedPromptText == null || resolvedPromptText.trim().isEmpty)) {
          issues.add('prompt_text_missing');
        }
        break;
      default:
        break;
    }
    return issues;
  }

  static List<String> _pairMappingIssues({
    required int leftCount,
    required int rightCount,
    required List<int> mapping,
  }) {
    final issues = <String>[];
    if (leftCount <= 0 || rightCount <= 0) return issues;
    if (mapping.isEmpty) {
      issues.add('mapping_missing');
      return issues;
    }
    if (mapping.length != leftCount) {
      issues.add('mapping_length_mismatch');
    }
    final used = <int>{};
    for (final target in mapping) {
      if (target < 0 || target >= rightCount) {
        issues.add('mapping_index_out_of_range');
        continue;
      }
      if (!used.add(target)) {
        issues.add('mapping_duplicate_targets');
      }
    }
    return issues.toSet().toList(growable: false);
  }

  static String instructionFor({
    required PilotExerciseItem item,
    String? resolvedPromptText,
  }) {
    final exerciseType = normalizeType(item.exerciseType);
    final coreInstruction = _coreInstructionFor(item, resolvedPromptText);
    if (coreInstruction != null && coreInstruction.trim().isNotEmpty) {
      return coreInstruction;
    }
    final instruction = _instructions[exerciseType];
    if (instruction != null) return instruction(item, resolvedPromptText);
    return 'Answer the question';
  }

  static String revealFor(PilotExerciseItem item) {
    final exerciseType = normalizeType(item.exerciseType);
    if (exerciseType == 'flashcard') {
      final payload = item.payload;
      final back = _payloadText(payload, const [
        'back',
        'translation',
        'definition',
        'explanation',
        'answer',
      ]);
      if (back != null && back.isNotEmpty) return 'Meaning: $back';
      final meaning = _promptMeaning(item);
      if (meaning != null && meaning.isNotEmpty) return 'Meaning: $meaning';
      return 'Card reviewed.';
    }
    if (exerciseType == 'character_writing') {
      return 'Character writing marked complete.';
    }
    if (exerciseType == 'reverse_recall') {
      final answers = _expectedReverseRecallAnswers(item);
      if (answers.isNotEmpty) return 'Correct: ${answers.first}';
      return 'Correct answer shown above.';
    }
    if (exerciseType == 'error_correction') {
      final answers = _expectedErrorCorrectionAnswers(item);
      if (answers.isNotEmpty) return 'Correct: ${answers.first}';
      return 'Correct answer shown above.';
    }
    if (exerciseType == 'cloze_select' && _isClozeTextMode(item)) {
      final answers = _expectedClozeTextAnswers(item);
      if (answers.isNotEmpty) return 'Correct: ${answers.first}';
      return 'Correct answer shown above.';
    }
    if (exerciseType == 'listen_write') {
      final answers = _expectedListenWriteAnswers(item);
      if (answers.isNotEmpty) return 'Correct: ${answers.first}';
      return 'Correct answer shown above.';
    }
    final reveal = _reveals[exerciseType];
    if (reveal != null) return reveal(item);
    if (item.answerIndex >= 0 && item.answerIndex < item.choices.length) {
      return 'Correct: ${item.choices[item.answerIndex]}';
    }
    return 'Correct answer shown above.';
  }

  static Widget? buildMediaSlot({
    required PilotExerciseItem item,
    required bool isSpeakingItem,
  }) {
    final exerciseType = normalizeType(item.exerciseType);
    if (isSpeakingItem || _speakingTypes.contains(exerciseType)) return null;
    final inlineAudioTypes = <String>{
      'audio_select',
      'dictation_select',
      'listen_write',
    };
    final imageUrl = _resolveImageUrl(item.payload['image_url']?.toString());
    final audioUrl =
        _audioTypes.contains(exerciseType) &&
            !inlineAudioTypes.contains(exerciseType)
        ? _audioUrlForItem(item)
        : null;
    final showImage = imageUrl != null && imageUrl.isNotEmpty;
    final showAudio = audioUrl != null && audioUrl.isNotEmpty;
    if (!showImage && !showAudio) return null;
    return ExerciseMediaSlot(
      imageUrl: imageUrl,
      audioUrl: audioUrl,
      showImagePlaceholder: false,
      showAudio: showAudio,
      enableAudio: false,
    );
  }

  static Widget buildExercise({
    required PilotExerciseItem item,
    required PracticeExerciseUiState state,
    required PracticeExerciseCallbacks callbacks,
    String? resolvedPromptText,
  }) {
    final exerciseType = normalizeType(item.exerciseType);
    final renderer = _renderers[exerciseType];
    if (renderer != null) {
      return renderer(item, state, callbacks, resolvedPromptText);
    }
    return Center(child: Text('Unsupported $exerciseType'));
  }

  static String skillForType(String exerciseType) {
    final normalizedType = normalizeType(exerciseType);
    return _skillByType[normalizedType] ?? 'meaning';
  }

  static String masterySkillFor(String skill) {
    return _masteryBySkill[skill] ?? 'meaning';
  }

  static AttemptSignal classifyAttemptSignal({
    required PilotExerciseItem item,
    required bool isCorrect,
    required int attemptsUsed,
    required int? latencyMs,
    double? speakingScore,
  }) {
    final type = normalizeType(item.exerciseType);
    final skill = skillForType(type);
    return AttemptSignalEngine.classify(
      AttemptSignalInput(
        isCorrect: isCorrect,
        attemptsUsed: attemptsUsed,
        latencyMs: latencyMs,
        exerciseType: type,
        skill: skill,
        speakingScore: speakingScore,
      ),
    );
  }

  static bool _isReadingCorrect(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
  ) {
    if (item.questions.isEmpty) return false;
    final safeIndex = state.readingQuestionIndex.clamp(
      0,
      item.questions.length - 1,
    );
    final question = item.questions[safeIndex];
    return state.selectedIndex == question.answerIndex;
  }

  static bool _isOrderSentenceCorrect(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
  ) {
    return state.orderChunks.join('|') == state.orderAnswer.join('|');
  }

  static bool _isOrderSentenceReady(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
  ) {
    final answerCount = state.orderAnswer.length;
    if (answerCount > 0) return state.orderChunks.length >= answerCount;
    final payloadCount = _payloadTokenChunks(item).length;
    if (payloadCount > 0) return state.orderChunks.length >= payloadCount;
    return false;
  }

  static bool _isMeaningMatchCorrect(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
  ) {
    return state.matchReady && state.matchCorrect;
  }

  static bool _isMeaningMatchReady(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
  ) {
    return state.matchReady;
  }

  static bool _validateReadingMicro(PilotExerciseItem item, String? _) {
    return item.reading != null && item.questions.isNotEmpty;
  }

  static bool _validateReadingSpanSelect(PilotExerciseItem item, String? _) {
    final passage =
        _payloadText(item.payload, const [
          'passage',
          'text',
          'reading',
          'content',
        ]) ??
        '';
    return passage.isNotEmpty && item.choices.length >= 2;
  }

  static bool _validateClozeSelect(PilotExerciseItem item, String? _) {
    final sentence =
        _payloadText(item.payload, const [
          'sentence',
          'text',
          'stem',
          'prompt',
          'passage',
        ]) ??
        '';
    if (sentence.isEmpty) return false;
    if (!_isClozeTextMode(item)) {
      return item.choices.isNotEmpty;
    }
    return _expectedClozeTextAnswers(item).isNotEmpty;
  }

  static bool _validateListenWrite(PilotExerciseItem item, String? promptText) {
    final hasPrompt =
        (promptText != null && promptText.trim().isNotEmpty) ||
        (_payloadText(item.payload, const [
              'prompt_text',
              'question',
              'prompt',
              'instruction',
            ]) !=
            null);
    final hasExpected = _expectedListenWriteAnswers(item).isNotEmpty;
    final hasAudio = _audioUrlForItem(item) != null;
    return hasPrompt && hasExpected && hasAudio;
  }

  static bool _validateFlashcard(PilotExerciseItem item, String? _) {
    final front = _flashcardFront(item);
    final back = _flashcardBack(item);
    final hanzi = _promptFront(item)?.trim();
    final meaning = _promptMeaning(item)?.trim();
    return (front != null && front.isNotEmpty) ||
        (back != null && back.isNotEmpty) ||
        (hanzi != null && hanzi.isNotEmpty) ||
        (meaning != null && meaning.isNotEmpty);
  }

  static bool _validateCharacterWriting(PilotExerciseItem item, String? _) {
    final payload = item.payload;
    final target =
        payload['target_character']?.toString().trim() ??
        payload['hanzi']?.toString().trim() ??
        item.prompt.hanzi?.trim() ??
        '';
    return target.isNotEmpty;
  }

  static bool _validateTrueFalse(PilotExerciseItem item, String? promptText) {
    final choices = item.choices;
    final hasChoices = choices.length >= 2;
    final hasPrompt =
        (promptText != null && promptText.trim().isNotEmpty) ||
        (item.payload['statement']?.toString().trim().isNotEmpty ?? false) ||
        (item.payload['question']?.toString().trim().isNotEmpty ?? false) ||
        (item.payload['text']?.toString().trim().isNotEmpty ?? false) ||
        (item.payload['prompt']?.toString().trim().isNotEmpty ?? false) ||
        (item.prompt.hanzi?.trim().isNotEmpty ?? false) ||
        (item.prompt.meaning?.trim().isNotEmpty ?? false);
    return hasChoices && hasPrompt;
  }

  static bool _validateReverseRecall(
    PilotExerciseItem item,
    String? promptText,
  ) {
    final hasPrompt =
        (promptText != null && promptText.trim().isNotEmpty) ||
        (item.payload['question']?.toString().trim().isNotEmpty ?? false) ||
        (item.payload['prompt']?.toString().trim().isNotEmpty ?? false) ||
        (item.payload['text']?.toString().trim().isNotEmpty ?? false) ||
        (item.prompt.hanzi?.trim().isNotEmpty ?? false) ||
        (item.prompt.meaning?.trim().isNotEmpty ?? false);
    return hasPrompt && _expectedReverseRecallAnswers(item).isNotEmpty;
  }

  static bool _validateErrorCorrection(
    PilotExerciseItem item,
    String? promptText,
  ) {
    final payload = item.payload;
    final hasPrompt =
        (promptText != null && promptText.trim().isNotEmpty) ||
        (payload['sentence']?.toString().trim().isNotEmpty ?? false) ||
        (payload['incorrect_sentence']?.toString().trim().isNotEmpty ??
            false) ||
        (payload['question']?.toString().trim().isNotEmpty ?? false) ||
        (payload['prompt']?.toString().trim().isNotEmpty ?? false);
    final hasTokenPayload =
        _errorCorrectionIncorrectTokens(item).isNotEmpty &&
        _errorCorrectionAnswerTokens(item).isNotEmpty;
    return hasPrompt &&
        (_expectedErrorCorrectionAnswers(item).isNotEmpty || hasTokenPayload);
  }

  static bool _validateOrderSentence(PilotExerciseItem item, String? _) {
    return _payloadTokenChunks(item).isNotEmpty;
  }

  static bool _validateMeaningMatch(PilotExerciseItem item, String? _) {
    final left = item.payload['left'] as List<dynamic>?;
    final right = item.payload['right'] as List<dynamic>?;
    return left != null && right != null && left.isNotEmpty && right.isNotEmpty;
  }

  static bool _validateAudioMatch(PilotExerciseItem item, String? _) {
    final right = item.payload['right'] as List<dynamic>?;
    if (right == null || right.isEmpty) return false;
    final left = item.payload['left'] as List<dynamic>?;
    if (left != null && left.isNotEmpty) return true;
    final audioUrls =
        item.payload['left_audio_urls'] as List<dynamic>? ??
        item.payload['audio_urls'] as List<dynamic>?;
    return audioUrls != null && audioUrls.isNotEmpty;
  }

  static bool _validateConversationSimulation(
    PilotExerciseItem item,
    String? promptText,
  ) {
    final hasChoices = item.choices.length >= 2;
    if (!hasChoices) return false;
    final payload = item.payload;
    final hasPrompt =
        (promptText != null && promptText.trim().isNotEmpty) ||
        (payload['scenario']?.toString().trim().isNotEmpty ?? false) ||
        (payload['context']?.toString().trim().isNotEmpty ?? false) ||
        (payload['question']?.toString().trim().isNotEmpty ?? false) ||
        (payload['speaker_a']?.toString().trim().isNotEmpty ?? false) ||
        (payload['speaker_a_text']?.toString().trim().isNotEmpty ?? false) ||
        (payload['speaker_a_zh']?.toString().trim().isNotEmpty ?? false) ||
        (item.prompt.hanzi?.trim().isNotEmpty ?? false) ||
        (item.prompt.meaning?.trim().isNotEmpty ?? false);
    return hasPrompt;
  }

  static bool _validateSpeakReadAloud(PilotExerciseItem item, String? _) {
    return _speakingSamples(item).isNotEmpty;
  }

  static bool _validateSpeakPromptedReply(
    PilotExerciseItem item,
    String? text,
  ) {
    if (_speakingSamples(item).isEmpty) return false;
    return (text ?? '').isNotEmpty;
  }

  static String _revealOrderSentence(PilotExerciseItem item) {
    final answer = (item.payload['answer'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    return 'Correct: ${answer.join('')}';
  }

  static String _revealMeaningMatch(PilotExerciseItem item) {
    final left = (item.payload['left'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final right = (item.payload['right'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    if (left.isEmpty || right.isEmpty) return 'Correct answer shown above.';
    return 'Correct: ${left.first} → ${right.first}';
  }

  static Widget _renderFlashcard(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? _,
  ) {
    final front = _flashcardFront(item) ?? 'Item';
    final pinyin = _promptPhonetic(item);
    final back = _flashcardBack(item);

    return _FlashcardExerciseView(front: front, pinyin: pinyin, back: back);
  }

  static Widget _renderCharacterWriting(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? _,
  ) {
    final payload = item.payload;
    final target =
        payload['target_character']?.toString().trim() ??
        payload['hanzi']?.toString().trim() ??
        item.prompt.hanzi?.trim() ??
        '字';
    final pinyin = payload['pinyin']?.toString().trim().isNotEmpty == true
        ? payload['pinyin'].toString().trim()
        : item.prompt.pinyin;
    final meaning = payload['meaning']?.toString().trim().isNotEmpty == true
        ? payload['meaning'].toString().trim()
        : item.prompt.meaning;

    return CharacterWritingExercise(
      targetCharacter: target,
      pinyin: pinyin,
      meaning: meaning,
    );
  }

  static Widget _renderTrueFalse(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? resolvedPromptText,
  ) {
    final payload = item.payload;
    final statement = (resolvedPromptText?.trim().isNotEmpty == true)
        ? resolvedPromptText!.trim()
        : (_payloadText(payload, const [
                'statement',
                'question',
                'text',
                'prompt',
              ]) ??
              _promptFront(item) ??
              _promptMeaning(item) ??
              'Is this statement true?');

    final tf = _resolveTrueFalseIndices(item);
    final choicesCount = item.choices.length;
    final maxIndex = choicesCount > 0 ? choicesCount - 1 : 1;
    final answerIndex = item.answerIndex.clamp(0, maxIndex);

    return TrueFalseExercise(
      statement: statement,
      falseIndex: tf.falseIndex,
      trueIndex: tf.trueIndex,
      answerIndex: answerIndex,
      selectedIndex: state.selectedIndex,
      isAnswered: state.isAnswered,
      onSelect: callbacks.onSelectIndex,
    );
  }

  static ({int falseIndex, int trueIndex}) _resolveTrueFalseIndices(
    PilotExerciseItem item,
  ) {
    final choices = item.choices;
    if (choices.length < 2) {
      return (falseIndex: 0, trueIndex: 1);
    }

    int? falseIndex;
    int? trueIndex;
    for (var i = 0; i < choices.length; i++) {
      final token = choices[i].trim().toLowerCase();
      if (falseIndex == null && _isFalseToken(token)) {
        falseIndex = i;
      }
      if (trueIndex == null && _isTrueToken(token)) {
        trueIndex = i;
      }
    }

    falseIndex ??= 0;
    trueIndex ??= 1;
    if (falseIndex == trueIndex) {
      trueIndex = falseIndex == 0 ? 1 : 0;
    }
    return (falseIndex: falseIndex, trueIndex: trueIndex);
  }

  static bool _isTrueToken(String token) {
    const trueTokens = <String>{
      'true',
      't',
      'yes',
      'y',
      'correct',
      'right',
      '是',
      '对',
      '正确',
      '真',
    };
    return trueTokens.contains(token);
  }

  static bool _isFalseToken(String token) {
    const falseTokens = <String>{
      'false',
      'f',
      'no',
      'n',
      'incorrect',
      'wrong',
      '否',
      '不',
      '不对',
      '错',
      '错误',
      '假',
    };
    return falseTokens.contains(token);
  }

  static Widget _renderMeaningSelect(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? _,
  ) {
    return MeaningSelectExercise(
      hanzi: _promptFront(item) ?? '',
      pinyin: _promptPhonetic(item),
      choices: item.choices,
      answerIndex: item.answerIndex,
      selectedIndex: state.selectedIndex,
      isAnswered: state.isAnswered,
      showPinyin: state.showPinyin,
      onTogglePinyin: callbacks.onTogglePinyin,
      onSelect: callbacks.onSelectIndex,
    );
  }

  static Widget _renderCharacterSelect(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? _,
  ) {
    final payloadMeaning = _payloadText(item.payload, const [
      'meaning',
      'translation',
      'definition',
      'prompt',
    ]);
    return CharacterSelectExercise(
      meaning: payloadMeaning ?? _promptMeaning(item) ?? '',
      pinyin: _promptPhonetic(item),
      choices: item.choices,
      answerIndex: item.answerIndex,
      selectedIndex: state.selectedIndex,
      isAnswered: state.isAnswered,
      showPinyin: state.showPinyin,
      onTogglePinyin: callbacks.onTogglePinyin,
      onSelect: callbacks.onSelectIndex,
    );
  }

  static Widget _renderAudioSelect(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? _,
  ) {
    return AudioSelectExercise(
      audioUrl: _audioUrlForItem(item),
      choiceType: item.choiceType ?? 'hanzi',
      choices: item.choices,
      answerIndex: item.answerIndex,
      selectedIndex: state.selectedIndex,
      isAnswered: state.isAnswered,
      onSelect: callbacks.onSelectIndex,
    );
  }

  static Widget _renderDictationSelect(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? resolvedPromptText,
  ) {
    return DictationSelectExercise(
      audioUrl: _audioUrlForItem(item),
      promptText:
          resolvedPromptText ?? 'Listen and choose the correct sentence',
      options: item.options.isNotEmpty
          ? item.options.map((o) => o.text).toList()
          : item.choices,
      answerIndex: item.answerIndex,
      selectedIndex: state.selectedIndex,
      isAnswered: state.isAnswered,
      showPrompt: false,
      onSelect: callbacks.onSelectIndex,
    );
  }

  static Widget _renderListenWrite(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? resolvedPromptText,
  ) {
    final prompt = (resolvedPromptText?.trim().isNotEmpty == true)
        ? resolvedPromptText!.trim()
        : (_payloadText(item.payload, const [
                'prompt_text',
                'question',
                'prompt',
                'instruction',
              ]) ??
              'Listen and write what you hear');
    return ClozeInputExercise(
      sentence: prompt,
      value: state.textAnswer,
      expectedAnswers: _expectedListenWriteAnswers(item),
      isAnswered: state.isAnswered,
      showSentenceCard: false,
      inputHint: 'Type what you hear',
      audioUrl: _audioUrlForItem(item),
      onChanged: callbacks.onTextChanged,
    );
  }

  static Widget _renderClozeSelect(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? _,
  ) {
    final sentence =
        _payloadText(item.payload, const [
          'sentence',
          'text',
          'stem',
          'prompt',
        ]) ??
        _payloadText(item.payload, const ['passage']) ??
        '';
    String? contextPassage = _payloadText(item.payload, const [
      'context_passage',
      'passage_context',
      'context',
      'paragraph',
      'passage',
    ]);
    final maxContextWordsRaw = item.payload['max_context_words'];
    int? maxContextWords;
    if (maxContextWordsRaw is int) {
      maxContextWords = maxContextWordsRaw > 0 ? maxContextWordsRaw : null;
    } else if (maxContextWordsRaw is String) {
      final parsed = int.tryParse(maxContextWordsRaw.trim());
      maxContextWords = (parsed != null && parsed > 0) ? parsed : null;
    }
    final normalizedSentence = sentence.toLowerCase().trim().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    if (contextPassage != null) {
      final normalizedContext = contextPassage.toLowerCase().trim().replaceAll(
        RegExp(r'\s+'),
        ' ',
      );
      if (normalizedContext.isEmpty ||
          normalizedContext == normalizedSentence) {
        contextPassage = null;
      }
    }
    final phraseModeValue = _payloadText(item.payload, const [
      'blank_mode',
      'choice_mode',
      'variant',
      'response_mode',
    ])?.toLowerCase();
    final phraseMode =
        phraseModeValue == 'phrase' ||
        phraseModeValue == 'phrase_select' ||
        phraseModeValue == 'clause' ||
        phraseModeValue == 'fragment';
    if (_isClozeTextMode(item)) {
      return ClozeInputExercise(
        sentence: sentence,
        value: state.textAnswer,
        expectedAnswers: _expectedClozeTextAnswers(item),
        isAnswered: state.isAnswered,
        onChanged: callbacks.onTextChanged,
      );
    }
    return ClozeSelectExercise(
      sentence: sentence,
      contextPassage: contextPassage,
      contextMaxWords: maxContextWords,
      phraseMode: phraseMode,
      choices: item.choices,
      answerIndex: item.answerIndex,
      selectedIndex: state.selectedIndex,
      isAnswered: state.isAnswered,
      onSelect: callbacks.onSelectIndex,
    );
  }

  static Widget _renderReverseRecall(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? resolvedPromptText,
  ) {
    final payload = item.payload;
    final promptText = (resolvedPromptText?.trim().isNotEmpty == true)
        ? resolvedPromptText!.trim()
        : (payload['question']?.toString().trim().isNotEmpty == true)
        ? payload['question'].toString().trim()
        : (payload['prompt']?.toString().trim().isNotEmpty == true)
        ? payload['prompt'].toString().trim()
        : (item.prompt.meaning?.trim().isNotEmpty == true)
        ? item.prompt.meaning!.trim()
        : (item.prompt.hanzi?.trim().isNotEmpty == true)
        ? item.prompt.hanzi!.trim()
        : 'Type the correct answer';

    return ClozeInputExercise(
      sentence: promptText,
      value: state.textAnswer,
      expectedAnswers: _expectedReverseRecallAnswers(item),
      isAnswered: state.isAnswered,
      onChanged: callbacks.onTextChanged,
    );
  }

  static Widget _renderErrorCorrection(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? resolvedPromptText,
  ) {
    if (_isErrorCorrectionTokenMode(item)) {
      final incorrectTokens = _errorCorrectionIncorrectTokens(item);
      final initialSelection = List<int>.generate(
        incorrectTokens.length,
        (index) => index,
        growable: false,
      );
      return OrderSentenceExercise(
        exerciseId: '${item.id}::error_correction',
        chunks: incorrectTokens,
        initialSelectedIndices: initialSelection,
        showWordBankShadowForSelected: false,
        onChanged: callbacks.onOrderChanged,
      );
    }

    final payload = item.payload;
    final incorrect =
        payload['incorrect_sentence']?.toString().trim() ??
        payload['sentence']?.toString().trim() ??
        '';
    final header = (resolvedPromptText?.trim().isNotEmpty == true)
        ? resolvedPromptText!.trim()
        : (payload['question']?.toString().trim().isNotEmpty == true)
        ? payload['question'].toString().trim()
        : 'Correct this sentence';
    final displayPrompt = incorrect.isNotEmpty ? '$header\n$incorrect' : header;

    return ClozeInputExercise(
      sentence: displayPrompt,
      value: state.textAnswer,
      expectedAnswers: _expectedErrorCorrectionAnswers(item),
      isAnswered: state.isAnswered,
      onChanged: callbacks.onTextChanged,
    );
  }

  static Widget _renderOrderSentence(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? _,
  ) {
    final payloadChunks = _payloadTokenChunks(item);
    final chunks = payloadChunks.isNotEmpty ? payloadChunks : state.orderAnswer;
    return OrderSentenceExercise(
      exerciseId: item.id,
      chunks: chunks,
      onChanged: callbacks.onOrderChanged,
    );
  }

  static Widget _renderMeaningMatch(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? _,
  ) {
    final left = (item.payload['left'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final right = (item.payload['right'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final mapping = (item.payload['mapping'] as List<dynamic>? ?? [])
        .map((e) => e as int)
        .toList();
    return MeaningMatchExercise(
      leftItems: left,
      rightItems: right,
      mapping: mapping,
      onStatus: callbacks.onMatchStatus,
    );
  }

  static Widget _renderAudioMatch(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? _,
  ) {
    final right = (item.payload['right'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final left = (item.payload['left'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final leftAudio =
        (item.payload['left_audio_urls'] as List<dynamic>? ??
                item.payload['audio_urls'] as List<dynamic>? ??
                const [])
            .map((e) => e.toString())
            .toList();
    final mapping = (item.payload['mapping'] as List<dynamic>? ?? [])
        .map((e) => e as int)
        .toList();
    final fallbackLeft = List<String>.generate(
      right.length,
      (i) => 'Audio ${i + 1}',
      growable: false,
    );
    final safeLeft = left.isNotEmpty ? left : fallbackLeft;
    return AudioMeaningMatchExercise(
      leftItems: safeLeft,
      leftAudioUrls: leftAudio,
      rightItems: right,
      mapping: mapping,
      onStatus: callbacks.onMatchStatus,
    );
  }

  static Widget _renderReadingMicro(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? _,
  ) {
    final reading = item.reading;
    final questions = item.questions;
    if (reading == null || questions.isEmpty) {
      return const Center(child: Text('Reading content missing'));
    }
    return ReadingMicroExercise(
      titleZh: reading.titleZh,
      titleEn: reading.titleEn,
      storyZh: reading.storyZh,
      storyEn: reading.storyEn,
      questionIndex: state.readingQuestionIndex,
      questions: questions
          .map(
            (q) => {
              'type': q.type,
              'prompt': q.prompt,
              'choices': q.choices,
              'answer_index': q.answerIndex,
            },
          )
          .toList(),
      selectedIndex: state.selectedIndex,
      isAnswered: state.isAnswered,
      onSelect: callbacks.onSelectIndex,
    );
  }

  static Widget _renderReadingSpanSelect(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? resolvedPromptText,
  ) {
    final payload = item.payload;
    final passage =
        _payloadText(payload, const [
          'passage',
          'text',
          'reading',
          'content',
        ]) ??
        '';
    final question = (resolvedPromptText?.trim().isNotEmpty == true)
        ? resolvedPromptText!.trim()
        : (payload['question']?.toString().trim().isNotEmpty == true)
        ? payload['question'].toString().trim()
        : 'Select the best answer from the passage';
    if (passage.isEmpty || item.choices.isEmpty) {
      return const Center(child: Text('Passage content missing'));
    }
    return ReadingSpanSelectExercise(
      passage: passage,
      question: question,
      choices: item.choices,
      answerIndex: item.answerIndex.clamp(0, item.choices.length - 1),
      selectedIndex: state.selectedIndex,
      isAnswered: state.isAnswered,
      onSelect: callbacks.onSelectIndex,
    );
  }

  static Widget _renderPinyinSelect(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? _,
  ) {
    return PinyinSelectExercise(
      hanzi: _promptFront(item) ?? '',
      choices: item.choices,
      answerIndex: item.answerIndex,
      selectedIndex: state.selectedIndex,
      isAnswered: state.isAnswered,
      onSelect: callbacks.onSelectIndex,
    );
  }

  static Widget _renderReplySelect(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? resolvedPromptText,
  ) {
    final prompt = _stripSpeakerPrefix(
      resolvedPromptText ?? (_promptFront(item) ?? ''),
    );
    return ReplySelectExercise(
      prompt: prompt,
      choices: item.choices,
      answerIndex: item.answerIndex,
      selectedIndex: state.selectedIndex,
      isAnswered: state.isAnswered,
      onSelect: callbacks.onSelectIndex,
    );
  }

  static Widget _renderConversationSimulation(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? resolvedPromptText,
  ) {
    final payload = item.payload;
    final scenario = (payload['scenario']?.toString().trim().isNotEmpty == true)
        ? payload['scenario'].toString().trim()
        : (payload['context']?.toString().trim().isNotEmpty == true)
        ? payload['context'].toString().trim()
        : '';
    final speakerLine = _stripSpeakerPrefix(
      (payload['speaker_a_zh']?.toString().trim().isNotEmpty == true)
          ? payload['speaker_a_zh'].toString().trim()
          : (payload['speaker_a_text']?.toString().trim().isNotEmpty == true)
          ? payload['speaker_a_text'].toString().trim()
          : (payload['speaker_a']?.toString().trim().isNotEmpty == true)
          ? payload['speaker_a'].toString().trim()
          : (_promptFront(item)?.trim().isNotEmpty == true)
          ? _promptFront(item)!.trim()
          : '',
    );
    final question = (payload['question']?.toString().trim().isNotEmpty == true)
        ? payload['question'].toString().trim()
        : (resolvedPromptText?.trim().isNotEmpty == true)
        ? resolvedPromptText!.trim()
        : 'Choose your reply';

    return ConversationSimulationExercise(
      scenario: scenario,
      speakerLine: speakerLine,
      question: question,
      choices: item.choices,
      answerIndex: item.answerIndex,
      selectedIndex: state.selectedIndex,
      isAnswered: state.isAnswered,
      onSelect: callbacks.onSelectIndex,
    );
  }

  static Widget _renderSpeakReadAloud(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? _,
  ) {
    final samples = _speakingSamples(item);
    return SpeakReadAloudExercise(
      hanzi: _promptFront(item) ?? '',
      pinyin: _promptPhonetic(item),
      meaning: _promptMeaning(item),
      sampleAnswers: samples,
      permissionGranted: state.speakingPermissionGranted,
      isRecording: state.speakingIsRecording,
      durationMs: state.speakingRecording?.durationMs,
      rating: state.speakingRating,
      transcript: state.speakingRecording?.transcript,
      score: state.speakingScore,
      onRequestPermission: callbacks.onRequestSpeakingPermission,
      onStartRecording: callbacks.onStartSpeakingRecording,
      onStopRecording: callbacks.onStopSpeakingRecording,
      onRate: callbacks.onSetSpeakingRating,
    );
  }

  static Widget _renderSpeakPromptedReply(
    PilotExerciseItem item,
    PracticeExerciseUiState state,
    PracticeExerciseCallbacks callbacks,
    String? resolvedPromptText,
  ) {
    final samples = _speakingSamples(item);
    return SpeakPromptedReplyExercise(
      promptText: resolvedPromptText ?? 'Respond aloud',
      meaning: _promptMeaning(item),
      sampleAnswers: samples,
      permissionGranted: state.speakingPermissionGranted,
      isRecording: state.speakingIsRecording,
      durationMs: state.speakingRecording?.durationMs,
      rating: state.speakingRating,
      transcript: state.speakingRecording?.transcript,
      score: state.speakingScore,
      onRequestPermission: callbacks.onRequestSpeakingPermission,
      onStartRecording: callbacks.onStartSpeakingRecording,
      onStopRecording: callbacks.onStopSpeakingRecording,
      onRate: callbacks.onSetSpeakingRating,
    );
  }

  static bool _isClozeTextMode(PilotExerciseItem item) {
    final payload = item.payload;
    final mode =
        payload['input_mode']?.toString().toLowerCase() ??
        payload['response_mode']?.toString().toLowerCase() ??
        '';
    if (mode == 'text' || mode == 'typing' || mode == 'input') return true;
    return item.choices.isEmpty;
  }

  static bool _isClozeTextCorrect(PilotExerciseItem item, String textAnswer) {
    final normalizedInput = _normalizeAnswerText(textAnswer);
    if (normalizedInput.isEmpty) return false;
    final expected = _expectedClozeTextAnswers(
      item,
    ).map(_normalizeAnswerText).where((s) => s.isNotEmpty).toSet();
    return expected.contains(normalizedInput);
  }

  static bool _isReverseRecallCorrect(
    PilotExerciseItem item,
    String textAnswer,
  ) {
    final normalizedInput = _normalizeAnswerText(textAnswer);
    if (normalizedInput.isEmpty) return false;
    final expected = _expectedReverseRecallAnswers(
      item,
    ).map(_normalizeAnswerText).where((s) => s.isNotEmpty).toSet();
    return expected.contains(normalizedInput);
  }

  static bool _isErrorCorrectionCorrect(
    PilotExerciseItem item,
    String textAnswer,
  ) {
    final normalizedInput = _normalizeAnswerText(textAnswer);
    if (normalizedInput.isEmpty) return false;
    final expected = _expectedErrorCorrectionAnswers(
      item,
    ).map(_normalizeAnswerText).where((s) => s.isNotEmpty).toSet();
    return expected.contains(normalizedInput);
  }

  static bool _isListenWriteCorrect(PilotExerciseItem item, String textAnswer) {
    final normalizedInput = _normalizeAnswerText(textAnswer);
    if (normalizedInput.isEmpty) return false;
    final expected = _expectedListenWriteAnswers(
      item,
    ).map(_normalizeAnswerText).where((s) => s.isNotEmpty).toSet();
    return expected.contains(normalizedInput);
  }

  static bool _isErrorCorrectionOrderCorrect(
    PilotExerciseItem item,
    List<String> orderedTokens,
  ) {
    final normalizedInput = _normalizeAnswerText(orderedTokens.join(' '));
    if (normalizedInput.isEmpty) return false;
    final expected = <String>{
      ..._expectedErrorCorrectionAnswers(
        item,
      ).map(_normalizeAnswerText).where((s) => s.isNotEmpty),
    };
    final tokenAnswer = _errorCorrectionAnswerTokens(item);
    if (tokenAnswer.isNotEmpty) {
      final normalizedTokenAnswer = _normalizeAnswerText(tokenAnswer.join(' '));
      if (normalizedTokenAnswer.isNotEmpty) {
        expected.add(normalizedTokenAnswer);
      }
    }
    return expected.contains(normalizedInput);
  }

  static List<String> _expectedReverseRecallAnswers(PilotExerciseItem item) {
    final payload = item.payload;
    final out = <String>{};

    final accepted = payload['accepted_answers'];
    if (accepted is List) {
      for (final value in accepted) {
        final text = value.toString().trim();
        if (text.isNotEmpty) out.add(text);
      }
    }

    final samples = payload['sample_answers'];
    if (samples is List) {
      for (final value in samples) {
        final text = value.toString().trim();
        if (text.isNotEmpty) out.add(text);
      }
    }

    final answer = payload['answer'];
    if (answer is String && answer.trim().isNotEmpty) {
      out.add(answer.trim());
    }

    if (out.isEmpty) {
      final front = _promptFront(item)?.trim();
      final meaning = _promptMeaning(item)?.trim();
      final hanzi = front;
      if (hanzi != null && hanzi.isNotEmpty) out.add(hanzi);
      if (meaning != null && meaning.isNotEmpty) out.add(meaning);
    }

    return out.toList(growable: false);
  }

  static List<String> _expectedListenWriteAnswers(PilotExerciseItem item) {
    final payload = item.payload;
    final out = <String>{};

    for (final key in const ['accepted_answers', 'sample_answers']) {
      final values = payload[key];
      if (values is! List) continue;
      for (final value in values) {
        final text = value.toString().trim();
        if (text.isNotEmpty) out.add(text);
      }
    }

    for (final key in const ['answer', 'transcript', 'target_text']) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) {
        out.add(value.trim());
      }
    }

    if (out.isEmpty &&
        item.answerIndex >= 0 &&
        item.answerIndex < item.choices.length) {
      final fallback = item.choices[item.answerIndex].trim();
      if (fallback.isNotEmpty) out.add(fallback);
    }

    return out.toList(growable: false);
  }

  static String? _flashcardFront(PilotExerciseItem item) {
    return _payloadText(item.payload, const [
          'front',
          'term',
          'text',
          'label',
          'title',
        ]) ??
        _promptFront(item);
  }

  static String? _flashcardBack(PilotExerciseItem item) {
    return _payloadText(item.payload, const [
          'back',
          'translation',
          'definition',
          'explanation',
          'answer',
        ]) ??
        _promptMeaning(item);
  }

  static String? _promptFront(PilotExerciseItem item) {
    final fromPayload = _payloadText(item.payload, const [
      'term',
      'text',
      'label',
      'title',
      'front',
    ]);
    if (fromPayload != null && fromPayload.isNotEmpty) return fromPayload;
    final hanzi = item.prompt.hanzi?.trim();
    if (hanzi != null && hanzi.isNotEmpty) return hanzi;
    final meaning = item.prompt.meaning?.trim();
    if (meaning != null && meaning.isNotEmpty) return meaning;
    return null;
  }

  static String? _promptPhonetic(PilotExerciseItem item) {
    final fromPayload = _payloadText(item.payload, const [
      'pinyin',
      'pronunciation',
      'phonetic',
    ]);
    if (fromPayload != null && fromPayload.isNotEmpty) return fromPayload;
    final pinyin = item.prompt.pinyin?.trim();
    if (pinyin != null && pinyin.isNotEmpty) return pinyin;
    return null;
  }

  static String? _promptMeaning(PilotExerciseItem item) {
    final fromPayload = _payloadText(item.payload, const [
      'meaning',
      'translation',
      'definition',
      'explanation',
    ]);
    if (fromPayload != null && fromPayload.isNotEmpty) return fromPayload;
    final meaning = item.prompt.meaning?.trim();
    if (meaning != null && meaning.isNotEmpty) return meaning;
    return null;
  }

  static String? _payloadText(Map<String, dynamic> payload, List<String> keys) {
    for (final key in keys) {
      final value = payload[key];
      if (value is String) {
        final text = value.trim();
        if (text.isNotEmpty) return text;
      } else if (value is num || value is bool) {
        final text = value.toString().trim();
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  static String _stripSpeakerPrefix(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.replaceFirst(
      RegExp(
        r'^\s*(?:[A-Za-z]|[\u4e00-\u9fff]|Speaker\s*[A-Za-z0-9]+)\s*[:：]\s*',
        caseSensitive: false,
      ),
      '',
    );
  }

  static List<String> _payloadTokenChunks(PilotExerciseItem item) {
    for (final key in const ['chunks', 'tokens', 'parts', 'segments']) {
      final raw = item.payload[key];
      if (raw is! List) continue;
      final values = raw
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList(growable: false);
      if (values.isNotEmpty) return values;
    }
    return const [];
  }

  static List<String> _speakingSamples(PilotExerciseItem item) {
    final out = <String>{};
    for (final key in const ['sample_answers', 'accepted_answers']) {
      final raw = item.payload[key];
      if (raw is! List) continue;
      for (final value in raw) {
        final text = value.toString().trim();
        if (text.isNotEmpty) out.add(text);
      }
    }
    final answer = item.payload['answer'];
    if (answer is String && answer.trim().isNotEmpty) {
      out.add(answer.trim());
    }
    return out.toList(growable: false);
  }

  static List<String> _expectedErrorCorrectionAnswers(PilotExerciseItem item) {
    final payload = item.payload;
    final out = <String>{};

    final accepted = payload['accepted_answers'];
    if (accepted is List) {
      for (final value in accepted) {
        final text = value.toString().trim();
        if (text.isNotEmpty) out.add(text);
      }
    }

    for (final key in const ['answer', 'correction', 'corrected_sentence']) {
      final value = payload[key];
      if (value is String && value.trim().isNotEmpty) {
        out.add(value.trim());
      }
    }

    final samples = payload['sample_answers'];
    if (samples is List) {
      for (final value in samples) {
        final text = value.toString().trim();
        if (text.isNotEmpty) out.add(text);
      }
    }

    final answerTokens = _errorCorrectionAnswerTokens(item);
    if (answerTokens.isNotEmpty) {
      out.add(answerTokens.join(' '));
    }

    return out.toList(growable: false);
  }

  static bool _isErrorCorrectionTokenMode(PilotExerciseItem item) {
    final incorrect = _errorCorrectionIncorrectTokens(item);
    final corrected = _errorCorrectionAnswerTokens(item);
    if (incorrect.isEmpty || corrected.isEmpty) return false;
    if (incorrect.length != corrected.length) return false;
    return _sameTokenBag(incorrect, corrected);
  }

  static bool _sameTokenBag(List<String> left, List<String> right) {
    final leftBag = <String, int>{};
    final rightBag = <String, int>{};

    String normalizeToken(String token) {
      final normalized = _normalizeAnswerText(token);
      if (normalized.isNotEmpty) return normalized;
      return token.trim().toLowerCase();
    }

    for (final token in left) {
      final key = normalizeToken(token);
      if (key.isEmpty) continue;
      leftBag[key] = (leftBag[key] ?? 0) + 1;
    }
    for (final token in right) {
      final key = normalizeToken(token);
      if (key.isEmpty) continue;
      rightBag[key] = (rightBag[key] ?? 0) + 1;
    }

    if (leftBag.length != rightBag.length) return false;
    for (final entry in leftBag.entries) {
      if (rightBag[entry.key] != entry.value) return false;
    }
    return true;
  }

  static List<String> _errorCorrectionIncorrectTokens(PilotExerciseItem item) {
    final payload = item.payload;
    for (final key in const [
      'incorrect_tokens',
      'tokens',
      'chunks',
      'segments',
    ]) {
      final raw = payload[key];
      if (raw is! List) continue;
      final values = raw
          .map((e) => e.toString().trim())
          .where((token) => token.isNotEmpty)
          .toList(growable: false);
      if (values.isNotEmpty) return values;
    }

    final sentence =
        payload['incorrect_sentence']?.toString().trim() ??
        payload['sentence']?.toString().trim() ??
        '';
    return _tokenizeSentence(sentence);
  }

  static List<String> _errorCorrectionAnswerTokens(PilotExerciseItem item) {
    final payload = item.payload;
    for (final key in const [
      'answer_tokens',
      'correct_tokens',
      'corrected_tokens',
    ]) {
      final raw = payload[key];
      if (raw is! List) continue;
      final values = raw
          .map((e) => e.toString().trim())
          .where((token) => token.isNotEmpty)
          .toList(growable: false);
      if (values.isNotEmpty) return values;
    }

    for (final key in const ['corrected_sentence', 'correction', 'answer']) {
      final value = payload[key];
      if (value is! String || value.trim().isEmpty) continue;
      final tokens = _tokenizeSentence(value);
      if (tokens.isNotEmpty) return tokens;
    }

    final accepted = payload['accepted_answers'];
    if (accepted is List) {
      for (final value in accepted) {
        final text = value.toString().trim();
        if (text.isEmpty) continue;
        final tokens = _tokenizeSentence(text);
        if (tokens.isNotEmpty) return tokens;
      }
    }

    return const [];
  }

  static List<String> _tokenizeSentence(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return const [];
    final splitBySpaces = normalized
        .split(RegExp(r'\s+'))
        .map((token) => token.trim())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
    if (splitBySpaces.length > 1) return splitBySpaces;
    return normalized.runes
        .map((rune) => String.fromCharCode(rune).trim())
        .where((token) => token.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _expectedClozeTextAnswers(PilotExerciseItem item) {
    final payload = item.payload;
    final out = <String>{};

    final accepted = payload['accepted_answers'];
    if (accepted is List) {
      for (final value in accepted) {
        final text = value.toString().trim();
        if (text.isNotEmpty) out.add(text);
      }
    }

    final answer = payload['answer'];
    if (answer is String && answer.trim().isNotEmpty) {
      out.add(answer.trim());
    }

    if (out.isEmpty &&
        item.answerIndex >= 0 &&
        item.answerIndex < item.choices.length) {
      out.add(item.choices[item.answerIndex]);
    }

    return out.toList(growable: false);
  }

  static String? _resolveImageUrl(String? imageUrl) {
    if (imageUrl == null || imageUrl.trim().isEmpty) return null;
    final normalized = imageUrl.trim();
    if (normalized.startsWith('http') || normalized.startsWith('assets/')) {
      return normalized;
    }
    if (normalized.startsWith('/')) {
      return '${AppConfig.apiBaseUrl}$normalized';
    }
    return normalized;
  }

  static String? _resolveAudioUrl(String? audioUrl) {
    if (audioUrl == null || audioUrl.trim().isEmpty) return null;
    final normalized = audioUrl.trim();
    if (normalized.startsWith('http')) return normalized;
    if (normalized.startsWith('/')) {
      return '${AppConfig.apiBaseUrl}$normalized';
    }
    return normalized;
  }

  static String? _audioUrlForItem(PilotExerciseItem item) {
    final direct = _resolveAudioUrl(item.audioUrl);
    if (direct != null) return direct;
    final payloadAudio = _payloadText(item.payload, const [
      'audio_url',
      'audio',
      'audioUrl',
      'prompt_audio_url',
      'promptAudioUrl',
      'sentence_audio_url',
      'sentenceAudioUrl',
      'voice_url',
      'voiceUrl',
      'tts_url',
      'ttsUrl',
      'speech_url',
      'speechUrl',
    ]);
    return _resolveAudioUrl(payloadAudio);
  }

  static String _normalizeAnswerText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(
          RegExp(r'[\s\.,!?;:"\-\(\)\[\]\{\}/\\_`~@#\$%\^&\*\+=<>|]+'),
          '',
        )
        .replaceAll(
          RegExp(
            r'[\u3001\u3002\uFF01\uFF1F\uFF1B\uFF1A\u201C\u201D\u2018\u2019\uFF08\uFF09\u3010\u3011\u300A\u300B\u2026]+',
          ),
          '',
        );
  }
}
