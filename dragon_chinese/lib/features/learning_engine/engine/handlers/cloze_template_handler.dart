import 'package:dragon_chinese/features/learning_engine/engine/template_handler.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_evaluation.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_response.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_spec.dart';

class ClozeTemplateHandler implements ExerciseTemplateHandler {
  @override
  List<String> get templateIds => const ['cloze_select'];

  @override
  String instructionFor(ExerciseSpec spec) => 'Complete the sentence';

  @override
  List<String> validate(ExerciseSpec spec) {
    final issues = <String>[];
    if (spec.promptText.trim().isEmpty) {
      issues.add('sentence_missing');
    }
    if (_isTextMode(spec)) {
      if (_expectedTextAnswers(spec).isEmpty) {
        issues.add('expected_answers_missing_for_text_mode');
      }
    } else {
      if (spec.choices.length < 2) {
        issues.add('choices_lt_2_for_select_mode');
      }
      final answerIndex = spec.answerIndex;
      if (answerIndex == null ||
          answerIndex < 0 ||
          answerIndex >= spec.choices.length) {
        issues.add('answer_index_out_of_range');
      }
    }
    return issues;
  }

  @override
  bool isReady(ExerciseSpec spec, ExerciseResponse response) {
    if (_isTextMode(spec)) {
      return response.typedText.trim().isNotEmpty;
    }
    return response.selectedIndex != null;
  }

  @override
  ExerciseEvaluation evaluate(ExerciseSpec spec, ExerciseResponse response) {
    if (!isReady(spec, response)) {
      return const ExerciseEvaluation(
        isReady: false,
        isCorrect: false,
        feedback: 'Provide an answer',
      );
    }

    if (_isTextMode(spec)) {
      final normalizedInput = _normalize(response.typedText);
      final expected = _expectedTextAnswers(
        spec,
      ).map(_normalize).where((s) => s.isNotEmpty).toSet();
      final isCorrect =
          normalizedInput.isNotEmpty && expected.contains(normalizedInput);
      return ExerciseEvaluation(isReady: true, isCorrect: isCorrect);
    }

    return ExerciseEvaluation(
      isReady: true,
      isCorrect: response.selectedIndex == spec.answerIndex,
    );
  }

  bool _isTextMode(ExerciseSpec spec) {
    final inputMode =
        (spec.payload['input_mode']?.toString().toLowerCase() ??
        spec.payload['response_mode']?.toString().toLowerCase() ??
        '');
    if (inputMode == 'text' || inputMode == 'typing' || inputMode == 'input') {
      return true;
    }
    return spec.choices.isEmpty;
  }

  List<String> _expectedTextAnswers(ExerciseSpec spec) {
    final out = <String>{};
    final accepted = spec.payload['accepted_answers'];
    if (accepted is List) {
      for (final value in accepted) {
        final text = value.toString().trim();
        if (text.isNotEmpty) out.add(text);
      }
    }
    final answer = spec.payload['answer'];
    if (answer is String && answer.trim().isNotEmpty) {
      out.add(answer.trim());
    }
    if (out.isEmpty &&
        spec.answerIndex != null &&
        spec.answerIndex! >= 0 &&
        spec.answerIndex! < spec.choices.length) {
      out.add(spec.choices[spec.answerIndex!]);
    }
    return out.toList(growable: false);
  }

  String _normalize(String value) {
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
