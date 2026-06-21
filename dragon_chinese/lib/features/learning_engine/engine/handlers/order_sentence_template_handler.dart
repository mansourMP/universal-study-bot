import 'package:dragon_chinese/features/learning_engine/engine/template_handler.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_evaluation.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_response.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_spec.dart';

class OrderSentenceTemplateHandler implements ExerciseTemplateHandler {
  @override
  List<String> get templateIds => const ['order_sentence'];

  @override
  String instructionFor(ExerciseSpec spec) => 'Order the sentence';

  @override
  List<String> validate(ExerciseSpec spec) {
    final issues = <String>[];
    if (spec.choices.isEmpty && spec.answerTokens.isEmpty) {
      issues.add('tokens_missing');
    }
    return issues;
  }

  @override
  bool isReady(ExerciseSpec spec, ExerciseResponse response) {
    final expectedCount = spec.answerTokens.isNotEmpty
        ? spec.answerTokens.length
        : spec.choices.length;
    return expectedCount > 0 && response.orderedTokens.length >= expectedCount;
  }

  @override
  ExerciseEvaluation evaluate(ExerciseSpec spec, ExerciseResponse response) {
    if (!isReady(spec, response)) {
      return const ExerciseEvaluation(
        isReady: false,
        isCorrect: false,
        feedback: 'Place all tokens',
      );
    }
    final expected = spec.answerTokens.isNotEmpty
        ? spec.answerTokens
        : spec.choices;
    final isCorrect =
        _normalize(response.orderedTokens) == _normalize(expected);
    return ExerciseEvaluation(isReady: true, isCorrect: isCorrect);
  }

  String _normalize(List<String> tokens) {
    return tokens.map((e) => e.trim()).join('|');
  }
}
