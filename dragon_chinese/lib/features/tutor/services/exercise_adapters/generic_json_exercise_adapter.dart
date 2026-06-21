import 'package:dragon_chinese/features/tutor/models/ai_exercise_schema.dart';
import 'package:dragon_chinese/features/tutor/services/exercise_adapters/exercise_provider_adapter.dart';

class GenericJsonExerciseAdapter implements ExerciseProviderAdapter {
  @override
  final String providerId;

  const GenericJsonExerciseAdapter({required this.providerId});

  @override
  bool supportsProvider(String provider) {
    final normalized = provider.trim().toLowerCase();
    return normalized == providerId || normalized.isEmpty;
  }

  @override
  AiExerciseSchema adapt(Map<String, dynamic> rawResponse) {
    return AiExerciseSchema.fromJson(rawResponse, sourceProvider: providerId);
  }
}

class OpenAiExerciseAdapter extends GenericJsonExerciseAdapter {
  const OpenAiExerciseAdapter() : super(providerId: 'openai');
}

class GeminiExerciseAdapter extends GenericJsonExerciseAdapter {
  const GeminiExerciseAdapter() : super(providerId: 'gemini');
}

class DeepSeekExerciseAdapter extends GenericJsonExerciseAdapter {
  const DeepSeekExerciseAdapter() : super(providerId: 'deepseek');
}
