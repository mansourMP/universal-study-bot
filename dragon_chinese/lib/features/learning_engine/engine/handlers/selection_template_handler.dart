import 'package:dragon_chinese/features/learning_engine/engine/template_handler.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_evaluation.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_response.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_spec.dart';

class SelectionTemplateHandler implements ExerciseTemplateHandler {
  static const List<String> _ids = [
    'meaning_select',
    'character_select',
    'pinyin_select',
    'audio_select',
    'reply_select',
  ];

  static const Map<String, String> _instructions = {
    'meaning_select': 'Choose the meaning',
    'character_select': 'Choose the characters',
    'pinyin_select': 'Choose the correct pinyin',
    'audio_select': 'Listen and choose',
    'reply_select': 'Choose the best reply',
  };

  @override
  List<String> get templateIds => _ids;

  @override
  String instructionFor(ExerciseSpec spec) {
    return _instructions[spec.templateId] ?? 'Choose one answer';
  }

  @override
  List<String> validate(ExerciseSpec spec) {
    final issues = <String>[];
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

  @override
  bool isReady(ExerciseSpec spec, ExerciseResponse response) {
    return response.selectedIndex != null;
  }

  @override
  ExerciseEvaluation evaluate(ExerciseSpec spec, ExerciseResponse response) {
    final selected = response.selectedIndex;
    if (selected == null) {
      return const ExerciseEvaluation(
        isReady: false,
        isCorrect: false,
        feedback: 'Select an answer',
      );
    }
    return ExerciseEvaluation(
      isReady: true,
      isCorrect: selected == spec.answerIndex,
    );
  }
}
