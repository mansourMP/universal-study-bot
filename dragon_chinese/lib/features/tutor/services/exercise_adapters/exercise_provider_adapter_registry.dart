import 'package:dragon_chinese/features/tutor/models/ai_exercise_schema.dart';
import 'package:dragon_chinese/features/tutor/services/exercise_adapters/exercise_provider_adapter.dart';
import 'package:dragon_chinese/features/tutor/services/exercise_adapters/generic_json_exercise_adapter.dart';

class ExerciseProviderAdapterRegistry {
  final List<ExerciseProviderAdapter> _adapters;

  const ExerciseProviderAdapterRegistry._(this._adapters);

  factory ExerciseProviderAdapterRegistry.defaults() {
    return const ExerciseProviderAdapterRegistry._([
      OpenAiExerciseAdapter(),
      GeminiExerciseAdapter(),
      DeepSeekExerciseAdapter(),
    ]);
  }

  ExerciseProviderAdapter resolve(String provider) {
    final normalized = provider.trim().toLowerCase();
    for (final adapter in _adapters) {
      if (adapter.supportsProvider(normalized)) return adapter;
    }
    return GenericJsonExerciseAdapter(
      providerId: normalized.isEmpty ? 'generic' : normalized,
    );
  }

  AiExerciseSchema adapt({
    required String provider,
    required Map<String, dynamic> rawResponse,
  }) {
    return resolve(provider).adapt(rawResponse);
  }
}
