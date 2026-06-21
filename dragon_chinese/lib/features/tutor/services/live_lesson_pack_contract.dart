import 'package:dragon_chinese/features/course/engine/practice_exercise_engine.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';

/// Contract checks for AI-generated live lesson packs before rendering.
class LiveLessonPackContract {
  const LiveLessonPackContract._();

  static PilotExercisePack filterSessionEnabled(PilotExercisePack pack) {
    final filtered = pack.items
        .where(
          (item) =>
              PracticeExerciseEngine.isSessionEnabledType(item.exerciseType),
        )
        .toList(growable: false);
    return PilotExercisePack(
      schemaVersion: pack.schemaVersion,
      generatedAt: pack.generatedAt,
      items: filtered,
    );
  }

  static List<String> validate({
    required PilotExercisePack pack,
    required Set<String> allowedTypes,
    int expectedItems = 0,
  }) {
    final issues = <String>[];
    if (pack.items.isEmpty) {
      issues.add('pack_empty');
      return issues;
    }
    if (expectedItems > 0 && pack.items.length != expectedItems) {
      issues.add(
        'item_count_mismatch expected=$expectedItems actual=${pack.items.length}',
      );
    }

    for (var i = 0; i < pack.items.length; i++) {
      final item = pack.items[i];
      final type = PracticeExerciseEngine.normalizeType(item.exerciseType);
      if (!PracticeExerciseEngine.isKnownType(type)) {
        issues.add('item[$i].unknown_type:$type');
      }
      if (!allowedTypes.contains(type)) {
        issues.add('item[$i].type_not_allowed:$type');
      }
      if (!PracticeExerciseEngine.isSessionEnabledType(type)) {
        issues.add('item[$i].type_disabled:$type');
      }
      final resolvedPrompt = item.promptText?.trim().isNotEmpty == true
          ? item.promptText
          : null;
      final valid = PracticeExerciseEngine.isItemValid(
        item: item,
        resolvedPromptText: resolvedPrompt,
      );
      if (!valid) {
        final itemIssues = PracticeExerciseEngine.contractIssuesFor(
          item: item,
          resolvedPromptText: resolvedPrompt,
        );
        issues.add('item[$i].invalid:${itemIssues.join("|")}');
      }
    }
    return issues;
  }
}
