import 'package:dragon_chinese/features/learning_engine/engine/handlers/order_sentence_template_handler.dart';
import 'package:dragon_chinese/features/learning_engine/engine/handlers/cloze_template_handler.dart';
import 'package:dragon_chinese/features/learning_engine/engine/handlers/reading_micro_template_handler.dart';
import 'package:dragon_chinese/features/learning_engine/engine/handlers/selection_template_handler.dart';
import 'package:dragon_chinese/features/learning_engine/engine/template_handler.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_evaluation.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_response.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_spec.dart';

class GenericExerciseEngine {
  GenericExerciseEngine(List<ExerciseTemplateHandler> handlers)
    : _handlers = _indexHandlers(handlers);

  final Map<String, ExerciseTemplateHandler> _handlers;

  static GenericExerciseEngine defaultEngine() {
    return GenericExerciseEngine([
      SelectionTemplateHandler(),
      OrderSentenceTemplateHandler(),
      ClozeTemplateHandler(),
      ReadingMicroTemplateHandler(),
    ]);
  }

  bool supports(String templateId) => _handlers.containsKey(templateId);

  String? instructionFor(ExerciseSpec spec) {
    final handler = _handlers[spec.templateId];
    if (handler == null) return null;
    return handler.instructionFor(spec);
  }

  List<String>? validate(ExerciseSpec spec) {
    final handler = _handlers[spec.templateId];
    if (handler == null) return null;
    return handler.validate(spec);
  }

  ExerciseEvaluation? evaluate(ExerciseSpec spec, ExerciseResponse response) {
    final handler = _handlers[spec.templateId];
    if (handler == null) return null;
    return handler.evaluate(spec, response);
  }

  static Map<String, ExerciseTemplateHandler> _indexHandlers(
    List<ExerciseTemplateHandler> handlers,
  ) {
    final out = <String, ExerciseTemplateHandler>{};
    for (final handler in handlers) {
      for (final templateId in handler.templateIds) {
        out[templateId] = handler;
      }
    }
    return out;
  }
}
