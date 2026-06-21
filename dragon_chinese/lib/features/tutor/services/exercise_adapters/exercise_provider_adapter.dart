import 'package:dragon_chinese/features/tutor/models/ai_exercise_schema.dart';

abstract class ExerciseProviderAdapter {
  String get providerId;

  bool supportsProvider(String provider) {
    return provider.trim().toLowerCase() == providerId;
  }

  AiExerciseSchema adapt(Map<String, dynamic> rawResponse);
}
