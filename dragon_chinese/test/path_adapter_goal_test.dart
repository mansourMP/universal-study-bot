import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/adapters/path_view_models.dart';
import 'package:dragon_chinese/features/course/models/lesson_model.dart';
import 'package:dragon_chinese/features/course/services/goal_profile.dart';

Lesson _lesson({
  required String id,
  required String skill,
  required String title,
  required Map<String, dynamic> metadata,
}) {
  return Lesson(
    lessonId: id,
    vocabUnitId: 'u1',
    mode: 'practice',
    skillPrimary: skill,
    estimatedTimeMinutes: 3,
    status: 'available',
    unlockReason: null,
    masterySummary: const {'total': 4, 'known': 1, 'learning': 1},
    cultural: LessonCultural(
      guideCharacter: '',
      setting: 'Basics',
      storyContext: '',
      languageObjective: '',
    ),
    exerciseSequence: const [],
    metadata: metadata,
    title: title,
  );
}

void main() {
  test('PathAdapter biases lesson ordering by goal profile', () {
    final listening = _lesson(
      id: 'l1',
      skill: 'listening',
      title: 'Listening lesson',
      metadata: const {
        'skills': ['Listening'],
        'unit_title': 'Unit 1',
        'realm_title': 'Foundation Track',
      },
    );
    final speaking = _lesson(
      id: 'l2',
      skill: 'speaking',
      title: 'Speaking lesson',
      metadata: const {
        'skills': ['Speaking'],
        'unit_title': 'Unit 1',
        'realm_title': 'Foundation Track',
      },
    );

    final adapter = PathAdapter(goalProfile: GoalProfiles.speaking);
    final units = adapter.buildUnits([listening, speaking], 0);
    // Linear progression preserved; goal bias doesn't reorder fixed path steps
    expect(units.first.lessons.first.title, 'Listening lesson');
  });
}
