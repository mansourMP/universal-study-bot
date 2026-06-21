import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dragon_chinese/features/course/services/practice_models.dart';

class PracticeStateStore {
  static const String _prefsKey = 'practice_state_v1';
  final Map<int, ConceptSkillState> _concepts;
  final Map<String, SkillTrend> _skillTrends;
  String? lastExerciseType;
  bool lastWasIncorrect;

  PracticeStateStore(
    this._concepts,
    this._skillTrends, {
    this.lastExerciseType,
    this.lastWasIncorrect = false,
  });

  static Future<PracticeStateStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return PracticeStateStore({}, {});
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final concepts = <int, ConceptSkillState>{};
    final rawConcepts = json['concepts'] as Map<String, dynamic>? ?? {};
    for (final entry in rawConcepts.entries) {
      final id = int.tryParse(entry.key);
      if (id == null || entry.value is! Map<String, dynamic>) continue;
      concepts[id] = ConceptSkillState.fromJson(entry.value);
    }
    final trends = <String, SkillTrend>{};
    final rawTrends = json['skill_trends'] as Map<String, dynamic>? ?? {};
    for (final entry in rawTrends.entries) {
      if (entry.value is Map<String, dynamic>) {
        trends[entry.key] = SkillTrend.fromJson(entry.value);
      }
    }
    return PracticeStateStore(
      concepts,
      trends,
      lastExerciseType: json['last_exercise_type']?.toString(),
      lastWasIncorrect: json['last_was_incorrect'] ?? false,
    );
  }

  static PracticeStateStore fromData({
    Map<int, ConceptSkillState>? concepts,
    Map<String, SkillTrend>? skillTrends,
    String? lastExerciseType,
    bool lastWasIncorrect = false,
  }) {
    return PracticeStateStore(
      concepts ?? {},
      skillTrends ?? {},
      lastExerciseType: lastExerciseType,
      lastWasIncorrect: lastWasIncorrect,
    );
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = {
      'concepts': _concepts.map((k, v) => MapEntry('$k', v.toJson())),
      'skill_trends': _skillTrends.map((k, v) => MapEntry(k, v.toJson())),
      'last_exercise_type': lastExerciseType,
      'last_was_incorrect': lastWasIncorrect,
    };
    await prefs.setString(_prefsKey, jsonEncode(json));
  }

  ConceptSkillState stateFor(int wordId) {
    return _concepts[wordId] ??
        ConceptSkillState(wordId: wordId, skills: {});
  }

  SkillState skillStateFor(int wordId, String skill) {
    final state = stateFor(wordId);
    return state.skill(skill);
  }

  SkillTrend skillTrendFor(String skill) {
    return _skillTrends[skill] ?? SkillTrend.initial();
  }

  void applyAttempt(AttemptEvent event) {
    final now = event.timestamp;
    final prev = stateFor(event.wordId);
    final current = prev.skill(event.skill);
    final baseInterval = _baseIntervalMs(event.skill);
    double nextStrength = current.strength;
    int nextStreak = current.streak;
    int nextLapses = current.lapses;

    if (event.isCorrect) {
      nextStrength = (current.strength + 0.12 + _attemptBonus(event.attemptsUsed))
          .clamp(0.0, 1.0);
      nextStreak = current.streak + 1;
    } else {
      nextStrength = (current.strength - 0.15).clamp(0.0, 1.0);
      nextStreak = 0;
      nextLapses = current.lapses + 1;
    }

    final interval = event.isCorrect
        ? (baseInterval * (1.2 + nextStrength * 2.0)).round()
        : (baseInterval * 0.5).round();
    final dueAt = now + interval;

    final updatedSkill = current.copyWith(
      strength: nextStrength,
      lastSeen: now,
      dueAt: dueAt,
      streak: nextStreak,
      lapses: nextLapses,
    );
    _concepts[event.wordId] =
        prev.copyWithSkill(event.skill, updatedSkill);

    final trend = skillTrendFor(event.skill);
    final fast = event.durationMs > 0 && event.durationMs < 2400;
    final nextTrend = event.isCorrect
        ? trend.copyWith(
            consecutiveIncorrect: 0,
            consecutiveCorrectFast:
                fast ? trend.consecutiveCorrectFast + 1 : 0,
            lastLatencyMs: event.durationMs,
          )
        : trend.copyWith(
            consecutiveIncorrect: trend.consecutiveIncorrect + 1,
            consecutiveCorrectFast: 0,
            lastLatencyMs: event.durationMs,
          );
    _skillTrends[event.skill] = nextTrend;
    lastExerciseType = event.exerciseType;
    lastWasIncorrect = !event.isCorrect;
  }

  int _baseIntervalMs(String skill) {
    switch (skill) {
      case 'meaning':
        return 12 * 60 * 60 * 1000;
      case 'characters':
        return 16 * 60 * 60 * 1000;
      case 'pinyin':
        return 18 * 60 * 60 * 1000;
      case 'listening':
        return 20 * 60 * 60 * 1000;
      case 'reading':
        return 22 * 60 * 60 * 1000;
      case 'production':
        return 20 * 60 * 60 * 1000;
      default:
        return 12 * 60 * 60 * 1000;
    }
  }

  double _attemptBonus(int attemptsUsed) {
    if (attemptsUsed <= 1) return 0.04;
    if (attemptsUsed == 2) return 0.02;
    return 0.0;
  }
}
