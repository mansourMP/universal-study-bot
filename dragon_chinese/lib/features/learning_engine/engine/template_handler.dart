import 'package:dragon_chinese/features/learning_engine/models/exercise_evaluation.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_response.dart';
import 'package:dragon_chinese/features/learning_engine/models/exercise_spec.dart';

abstract class ExerciseTemplateHandler {
  List<String> get templateIds;

  String instructionFor(ExerciseSpec spec);

  List<String> validate(ExerciseSpec spec);

  bool isReady(ExerciseSpec spec, ExerciseResponse response);

  ExerciseEvaluation evaluate(ExerciseSpec spec, ExerciseResponse response);
}
