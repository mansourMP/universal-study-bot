import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/tutor/services/live_lesson_pack_contract.dart';

PilotExercisePack _pack(List<Map<String, dynamic>> items) {
  return PilotExercisePack.fromJson({
    'schema_version': 1,
    'generated_at': '2026-02-24T00:00:00Z',
    'items': items,
  });
}

void main() {
  test('validates a clean live lesson pack', () {
    final pack = _pack([
      {
        'id': 'ex_1',
        'exercise_type': 'meaning_select',
        'prompt_text': 'Choose the meaning',
        'choices': ['hello', 'goodbye'],
        'answer_index': 0,
        'payload': <String, dynamic>{},
      },
      {
        'id': 'ex_2',
        'exercise_type': 'order_sentence',
        'prompt_text': 'Order the sentence',
        'choices': const [],
        'answer_index': 0,
        'payload': <String, dynamic>{
          'chunks': ['我', '喜欢', '中文'],
          'answer': ['我', '喜欢', '中文'],
        },
      },
    ]);

    final issues = LiveLessonPackContract.validate(
      pack: pack,
      allowedTypes: {'meaning_select', 'order_sentence'},
      expectedItems: 2,
    );

    expect(issues, isEmpty);
  });

  test('flags disallowed types', () {
    final pack = _pack([
      {
        'id': 'ex_1',
        'exercise_type': 'character_select',
        'prompt_text': 'Select character',
        'choices': ['你', '我'],
        'answer_index': 0,
        'payload': <String, dynamic>{},
      },
    ]);

    final issues = LiveLessonPackContract.validate(
      pack: pack,
      allowedTypes: {'meaning_select'},
      expectedItems: 1,
    );

    expect(issues.any((issue) => issue.contains('type_not_allowed')), isTrue);
  });

  test('filterSessionEnabled removes disabled exercise types', () {
    final pack = _pack([
      {
        'id': 'ex_1',
        'exercise_type': 'reverse_recall',
        'prompt_text': 'Type answer',
        'choices': const [],
        'answer_index': 0,
        'payload': <String, dynamic>{
          'answer': '你好',
          'accepted_answers': ['你好'],
        },
      },
      {
        'id': 'ex_2',
        'exercise_type': 'meaning_select',
        'prompt_text': 'Choose meaning',
        'choices': ['hello', 'goodbye'],
        'answer_index': 0,
        'payload': <String, dynamic>{},
      },
    ]);

    final filtered = LiveLessonPackContract.filterSessionEnabled(pack);

    expect(filtered.items, hasLength(1));
    expect(filtered.items.first.exerciseType, 'meaning_select');
  });
}
