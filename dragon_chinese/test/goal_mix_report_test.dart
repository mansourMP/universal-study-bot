import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';
import 'package:dragon_chinese/features/course/services/goal_profile.dart';
import 'package:dragon_chinese/features/course/services/practice_scheduler.dart';
import 'package:dragon_chinese/features/course/services/practice_state_store.dart';
import 'package:dragon_chinese/features/course/services/practice_models.dart';

void main() {
  test('Goal mix report (counts by skill/type)', () {
    final file = File('assets/pilot/hsk1_exercises_v1.json');
    if (!file.existsSync()) {
      print('Goal mix report skipped: pack not found.');
      return;
    }
    final pack = PilotExercisePack.fromRawJson(file.readAsStringSync());
    final builder = PracticeSessionBuilder();
    final store = PracticeStateStore.fromData();
    const dateBucket = '2026-02-03';

    for (final goal in GoalType.values) {
      final profile = GoalProfiles.forType(goal);
      final plan = builder.buildPlan(
        pack: pack,
        state: store,
        seed: 'goal-mix',
        dateBucket: dateBucket,
        goalProfile: profile,
        config: const PracticeSchedulerConfig(totalCount: 16),
      );
      final skillCounts = <String, int>{};
      final typeCounts = <String, int>{};
      for (final item in plan.items) {
        skillCounts[item.skill] = (skillCounts[item.skill] ?? 0) + 1;
        typeCounts[item.exerciseType] = (typeCounts[item.exerciseType] ?? 0) + 1;
      }
      print('Goal: ${profile.label}');
      print('Skills: $skillCounts');
      print('Types: $typeCounts');
      print('---');
    }
    expect(true, isTrue);
  });
}
