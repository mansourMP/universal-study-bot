import 'package:dragon_chinese/features/course/services/goal_profile.dart';

class ContextTemplateResolver {
  final GoalProfile profile;

  ContextTemplateResolver(this.profile);

  String resolvePrompt({
    required int wordId,
    required String? unitId,
    required String exerciseType,
    required int index,
    String? word,
    String? meaning,
  }) {
    final templates = profile.contextTemplates;
    if (templates.isEmpty) return _fallback(word, unitId);
    final hash = _stableHash(
      '${profile.goal.name}|$wordId|$unitId|$exerciseType|$index',
    );
    final template = templates[hash % templates.length];
    return _applyTemplate(template, word, unitId, meaning);
  }

  String resolveObjective({
    required String unitTitle,
    required int index,
  }) {
    final templates = profile.contextTemplates;
    if (templates.isEmpty) return 'Practice $unitTitle phrases';
    final hash = _stableHash('${profile.goal.name}|$unitTitle|$index');
    final template = templates[hash % templates.length];
    return template.replaceAll('{unit}', unitTitle);
  }

  String _applyTemplate(String template, String? word, String? unitId, String? meaning) {
    final fallbackWord = word?.trim().isNotEmpty == true
        ? word!
        : (meaning?.trim().isNotEmpty == true ? meaning! : 'this word');
    final unitLabel = unitId == null || unitId.trim().isEmpty
        ? 'this unit'
        : unitId;
    return template
        .replaceAll('{word}', fallbackWord)
        .replaceAll('{unit}', unitLabel);
  }

  String _fallback(String? word, String? unitId) {
    final unitLabel = unitId == null || unitId.trim().isEmpty
        ? 'this unit'
        : unitId;
    final fallbackWord = word?.trim().isNotEmpty == true ? word! : 'this word';
    return 'Practice $fallbackWord in $unitLabel';
  }

  int _stableHash(String input) {
    const int fnvPrime = 0x01000193;
    int hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash;
  }
}
