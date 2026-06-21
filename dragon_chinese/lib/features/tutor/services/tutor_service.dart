import 'package:dragon_chinese/core/net/endpoints.dart';
import 'package:dragon_chinese/core/network/api_client.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/tutor/models/tutor_models.dart';
import 'package:dragon_chinese/features/tutor/models/ai_exercise_schema.dart';
import 'package:dragon_chinese/features/tutor/services/exercise_adapters/exercise_provider_adapter_registry.dart';
import 'package:dragon_chinese/features/tutor/services/exercise_bridge/ai_exercise_pack_bridge.dart';

class TutorService {
  final ApiClient _api;
  final ExerciseProviderAdapterRegistry _exerciseAdapterRegistry;

  TutorService({
    ApiClient? api,
    ExerciseProviderAdapterRegistry? exerciseAdapterRegistry,
  }) : _api = api ?? ApiClient(),
       _exerciseAdapterRegistry =
           exerciseAdapterRegistry ??
           ExerciseProviderAdapterRegistry.defaults();

  Future<TutorSuggestionBundle> fetchSuggestions({
    String languageCode = 'zh',
  }) async {
    final data = await _api.getJson(
      Endpoints.tutorSuggestions,
      query: {'language_code': languageCode},
    );
    return TutorSuggestionBundle.fromJson(data);
  }

  Future<TutorChatReply> sendMessage({
    required String message,
    required List<TutorMessage> history,
    List<String> contextWords = const [],
    String languageCode = 'zh',
    String aiProvider = 'gemini',
  }) async {
    final data = await _api.postJson(
      Endpoints.tutorChat,
      body: {
        'message': message,
        'history': history.map((m) => m.toJson()).toList(),
        'context_words': contextWords,
        'language_code': languageCode,
        'ai_provider': aiProvider,
        'allow_fallback': true,
      },
    );
    return TutorChatReply.fromJson(data);
  }

  Future<TutorConversationSnapshot> fetchConversationHistory({
    String languageCode = 'zh',
  }) async {
    final data = await _api.getJson(
      Endpoints.tutorHistory,
      query: {'language_code': languageCode},
    );
    return TutorConversationSnapshot.fromJson(data);
  }

  Future<void> saveConversationHistory({
    required List<TutorMessage> messages,
    required List<String> contextWords,
    required String preferredProvider,
    String languageCode = 'zh',
  }) async {
    await _api.putJson(
      Endpoints.tutorHistory,
      body: {
        'messages': messages.map((m) => m.toJson()).toList(),
        'context_words': contextWords,
        'preferred_provider': preferredProvider,
        'language_code': languageCode,
      },
    );
  }

  Future<void> clearConversationHistory({String languageCode = 'zh'}) async {
    await _api.deleteJson(
      '${Endpoints.tutorHistory}?language_code=$languageCode',
    );
  }

  /// Normalizes provider-specific exercise payloads to one internal schema.
  AiExerciseSchema normalizeExerciseSchema({
    required String provider,
    required Map<String, dynamic> rawResponse,
  }) {
    final schema = _exerciseAdapterRegistry.adapt(
      provider: provider,
      rawResponse: rawResponse,
    );
    final issues = schema.validate();
    if (issues.isNotEmpty) {
      throw FormatException(
        'Invalid exercise schema from $provider: ${issues.join(' | ')}',
      );
    }
    return schema;
  }

  /// Bridge for existing practice/exercise UI pipeline.
  PilotExercisePack buildPilotPackFromSchema({
    required String provider,
    required Map<String, dynamic> rawResponse,
  }) {
    final schema = normalizeExerciseSchema(
      provider: provider,
      rawResponse: rawResponse,
    );
    return AiExercisePackBridge.toPilotPack(schema);
  }
}
