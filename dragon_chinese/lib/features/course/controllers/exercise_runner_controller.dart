import 'package:dragon_chinese/features/course/models/lesson_model.dart';

class ExerciseRunnerController {
  const ExerciseRunnerController();

  bool isTeaching(LessonExercise ex) {
    return ex.options?.isEmpty ?? true;
  }

  bool isCorrect(LessonExercise ex, String? selectedOption) {
    return (ex.options?.isEmpty ?? true) || selectedOption == ex.answer;
  }
}
