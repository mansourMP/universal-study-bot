import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/tutor/models/ai_exercise_schema.dart';
import 'package:dragon_chinese/features/tutor/services/exercise_adapters/exercise_provider_adapter_registry.dart';
import 'package:dragon_chinese/features/tutor/services/exercise_bridge/ai_exercise_pack_bridge.dart';
import 'package:dragon_chinese/features/tutor/services/tutor_service.dart';

void main() {
  test('adapts OpenAI-style nested payload into internal schema', () {
    final registry = ExerciseProviderAdapterRegistry.defaults();
    final raw = <String, dynamic>{
      'data': {
        'schema_version': 2,
        'generated_at': '2026-02-24T00:00:00Z',
        'items': [
          {
            'id': 'ex_1',
            'exercise_type': 'meaning_select',
            'prompt_text': '你好 means?',
            'choices': ['hello', 'goodbye'],
            'answer_index': 0,
            'skill': 'meaning',
            'meta': {
              'hsk_level': 1,
              'tags': ['intro'],
            },
          },
        ],
      },
    };

    final schema = registry.adapt(provider: 'openai', rawResponse: raw);

    expect(schema.schemaVersion, 2);
    expect(schema.sourceProvider, 'openai');
    expect(schema.items, hasLength(1));
    expect(schema.items.first.exerciseType, 'meaning_select');
    expect(schema.validate(), isEmpty);
  });

  test('adapts Gemini-style exercises/options payload', () {
    final registry = ExerciseProviderAdapterRegistry.defaults();
    final raw = <String, dynamic>{
      'exercises': [
        {
          'exercise_id': 'g_1',
          'type': 'dictation_select',
          'question': 'Choose what you heard',
          'options': [
            {'id': 'a', 'text': '我喜欢你。'},
            {'id': 'b', 'text': '你喜欢我。'},
          ],
          'correct_option_id': 'b',
          'audio_url': '/static/audio/sample.mp3',
        },
      ],
    };

    final schema = registry.adapt(provider: 'gemini', rawResponse: raw);

    expect(schema.items, hasLength(1));
    expect(schema.items.first.id, 'g_1');
    expect(schema.items.first.answerIndex, 1);
    expect(schema.items.first.choices, hasLength(2));
    expect(schema.validate(), isEmpty);
  });

  test('validation catches invalid items', () {
    final schema = AiExerciseSchema.fromJson({
      'source_provider': 'deepseek',
      'items': [
        {
          'id': 'bad_1',
          'exercise_type': 'meaning_select',
          'prompt_text': 'Bad sample',
          'choices': ['A', 'B'],
          'answer_index': 4,
        },
      ],
    }, sourceProvider: 'deepseek');

    final issues = schema.validate();

    expect(issues, isNotEmpty);
    expect(issues.any((e) => e.contains('answer_index out of bounds')), isTrue);
  });

  test('bridge converts internal schema to PilotExercisePack', () {
    final schema = AiExerciseSchema.fromJson({
      'schema_version': 1,
      'source_provider': 'openai',
      'generated_at': '2026-02-24T00:00:00Z',
      'items': [
        {
          'id': 'bridge_1',
          'exercise_type': 'audio_select',
          'prompt_text': 'Listen and choose',
          'choices': ['你', '我', '他'],
          'answer_index': 1,
          'audio_url': '/audio/a1.mp3',
          'meta': {'hsk_level': 2},
        },
      ],
    }, sourceProvider: 'openai');

    final pack = AiExercisePackBridge.toPilotPack(schema);

    expect(pack.schemaVersion, 1);
    expect(pack.items, hasLength(1));
    expect(pack.items.first.exerciseType, 'audio_select');
    expect(pack.items.first.answerIndex, 1);
    expect(pack.items.first.requiredAssets.audio, isTrue);
  });

  test(
    'TutorService exposes schema normalization and bridging entrypoints',
    () {
      final service = TutorService();

      final schema = service.normalizeExerciseSchema(
        provider: 'openai',
        rawResponse: {
          'items': [
            {
              'id': 'svc_1',
              'exercise_type': 'meaning_select',
              'prompt_text': 'Test prompt',
              'choices': ['A', 'B'],
              'answer_index': 0,
            },
          ],
        },
      );

      final pack = service.buildPilotPackFromSchema(
        provider: 'openai',
        rawResponse: {
          'items': [
            {
              'id': 'svc_2',
              'exercise_type': 'meaning_select',
              'prompt_text': 'Test prompt',
              'choices': ['A', 'B'],
              'answer_index': 0,
            },
          ],
        },
      );

      expect(schema.items.first.id, 'svc_1');
      expect(pack.items.first.id, 'svc_2');
    },
  );
}
