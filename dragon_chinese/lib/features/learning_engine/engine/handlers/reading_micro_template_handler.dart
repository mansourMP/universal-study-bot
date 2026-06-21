import 'package:dragon_chinese/features/learning_engine/engine/template_handler.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_evaluation.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_response.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_spec.dart';

class ReadingMicroTemplateHandler implements ExerciseTemplateHandler {
  @override
  List<String> get templateIds => const [
    'reading_micro',
    'reading_span_select',
  ];

  @override
  String instructionFor(ExerciseSpec spec) {
    if (spec.templateId == 'reading_span_select') {
      return 'Read and select the answer';
    }
    return 'Read the passage and answer';
  }

  @override
  List<String> validate(ExerciseSpec spec) {
    if (spec.templateId == 'reading_span_select') {
      return _validateReadingSpanSelect(spec);
    }
    final issues = <String>[];
    if (!_hasPassageText(spec)) {
      issues.add('passage_text_missing');
    }
    final questions = _questions(spec);
    if (questions.isEmpty) {
      issues.add('questions_empty');
      return issues;
    }

    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final choices = (q['choices'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(growable: false);
      final answerIndex = (q['answer_index'] is int)
          ? q['answer_index'] as int
          : -1;
      if (choices.length < 2) {
        issues.add('question_${i + 1}_choices_lt_2');
      }
      if (answerIndex < 0 || answerIndex >= choices.length) {
        issues.add('question_${i + 1}_answer_index_out_of_range');
      }
    }

    return issues;
  }

  @override
  bool isReady(ExerciseSpec spec, ExerciseResponse response) {
    return response.selectedIndex != null;
  }

  @override
  ExerciseEvaluation evaluate(ExerciseSpec spec, ExerciseResponse response) {
    if (!isReady(spec, response)) {
      return const ExerciseEvaluation(
        isReady: false,
        isCorrect: false,
        feedback: 'Select an answer',
      );
    }

    if (spec.templateId == 'reading_span_select') {
      final answerIndex = spec.answerIndex ?? -1;
      return ExerciseEvaluation(
        isReady: true,
        isCorrect: response.selectedIndex == answerIndex,
      );
    }

    final questions = _questions(spec);
    if (questions.isEmpty) {
      return const ExerciseEvaluation(
        isReady: false,
        isCorrect: false,
        errors: ['questions_empty'],
      );
    }

    final requestedIndex = response.metadata['question_index'];
    final questionIndex = (requestedIndex is int) ? requestedIndex : 0;
    final safeIndex = questionIndex.clamp(0, questions.length - 1);
    final q = questions[safeIndex];
    final answerIndex = (q['answer_index'] is int)
        ? q['answer_index'] as int
        : -1;
    final selected = response.selectedIndex ?? -1;

    return ExerciseEvaluation(
      isReady: true,
      isCorrect: selected == answerIndex,
    );
  }

  List<Map<String, dynamic>> _questions(ExerciseSpec spec) {
    final raw = spec.payload['questions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }

  bool _hasPassageText(ExerciseSpec spec) {
    final storyZh = spec.payload['reading_story_zh']?.toString().trim() ?? '';
    final storyEn = spec.payload['reading_story_en']?.toString().trim() ?? '';
    final passage = spec.payload['passage']?.toString().trim() ?? '';
    return storyZh.isNotEmpty || storyEn.isNotEmpty || passage.isNotEmpty;
  }

  List<String> _validateReadingSpanSelect(ExerciseSpec spec) {
    final issues = <String>[];
    if (!_hasPassageText(spec)) {
      issues.add('passage_text_missing');
    }
    if (spec.choices.length < 2) {
      issues.add('choices_lt_2');
    }
    final answerIndex = spec.answerIndex;
    if (answerIndex == null ||
        answerIndex < 0 ||
        answerIndex >= spec.choices.length) {
      issues.add('answer_index_out_of_range');
    }
    return issues;
  }
}
