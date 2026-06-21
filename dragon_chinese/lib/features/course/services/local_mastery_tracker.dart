import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MasteryStat {
  final double score;
  final int attempts;
  final int correct;
  final int wrongStreak;

  MasteryStat({
    required this.score,
    required this.attempts,
    required this.correct,
    required this.wrongStreak,
  });

  MasteryStat copyWith({
    double? score,
    int? attempts,
    int? correct,
    int? wrongStreak,
  }) {
    return MasteryStat(
      score: score ?? this.score,
      attempts: attempts ?? this.attempts,
      correct: correct ?? this.correct,
      wrongStreak: wrongStreak ?? this.wrongStreak,
    );
  }

  Map<String, dynamic> toJson() => {
        'score': score,
        'attempts': attempts,
        'correct': correct,
        'wrongStreak': wrongStreak,
      };

  factory MasteryStat.fromJson(Map<String, dynamic> json) {
    return MasteryStat(
      score: (json['score'] is num) ? (json['score'] as num).toDouble() : 50,
      attempts: json['attempts'] ?? 0,
      correct: json['correct'] ?? 0,
      wrongStreak: json['wrongStreak'] ?? 0,
    );
  }
}

class MasterySnapshot {
  final Map<String, double> skillScores;
  final Map<String, int> skillAttempts;

  MasterySnapshot({required this.skillScores, required this.skillAttempts});

  double overallScore(Map<String, double> weights) {
    double weighted = 0;
    double totalWeight = 0;
    for (final entry in weights.entries) {
      final score = skillScores[entry.key];
      if (score == null) continue;
      weighted += score * entry.value;
      totalWeight += entry.value;
    }
    if (totalWeight == 0) return 0;
    return weighted / totalWeight;
  }

  String? weakestSkill() {
    String? weakest;
    double lowest = 101;
    for (final entry in skillScores.entries) {
      if (entry.value < lowest) {
        lowest = entry.value;
        weakest = entry.key;
      }
    }
    return weakest;
  }
}

class LocalMasteryTracker {
  static const String _prefsKey = 'local_mastery_v1';
  final Map<String, MasteryStat> _stats;

  LocalMasteryTracker(this._stats);

  static Future<LocalMasteryTracker> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return LocalMasteryTracker({});
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final stats = <String, MasteryStat>{};
    data.forEach((key, value) {
      stats[key] = MasteryStat.fromJson(value as Map<String, dynamic>);
    });
    return LocalMasteryTracker(stats);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _stats.map((key, value) => MapEntry(key, value.toJson()));
    await prefs.setString(_prefsKey, jsonEncode(data));
  }

  void recordAttempt({
    required int conceptId,
    required String skillBucket,
    required bool isCorrect,
    required bool isExamMode,
    required bool isTimed,
  }) {
    final key = '$conceptId:$skillBucket';
    final current = _stats[key] ??
        MasteryStat(score: 50, attempts: 0, correct: 0, wrongStreak: 0);
    final attempts = current.attempts + 1;
    final correct = current.correct + (isCorrect ? 1 : 0);

    double delta;
    if (isCorrect) {
      delta = isExamMode ? (isTimed ? 12 : 10) : 8;
      if (current.wrongStreak > 0) {
        delta += (current.wrongStreak * 1.5).clamp(0, 4);
      }
    } else {
      delta = isExamMode ? (isTimed ? -15 : -10) : -8;
      delta -= (current.wrongStreak * 2).clamp(0, 8);
    }

    final newScore = (current.score + delta).clamp(0, 100).toDouble();
    final newWrongStreak = isCorrect ? 0 : current.wrongStreak + 1;

    _stats[key] = current.copyWith(
      score: newScore,
      attempts: attempts,
      correct: correct,
      wrongStreak: newWrongStreak,
    );
  }

  MasterySnapshot snapshot() {
    final skillTotals = <String, double>{};
    final skillCounts = <String, int>{};
    _stats.forEach((key, stat) {
      final parts = key.split(':');
      if (parts.length < 2) return;
      final skill = parts[1];
      skillTotals[skill] = (skillTotals[skill] ?? 0) + stat.score;
      skillCounts[skill] = (skillCounts[skill] ?? 0) + 1;
    });
    final skillScores = <String, double>{};
    skillTotals.forEach((skill, total) {
      final count = skillCounts[skill] ?? 1;
      skillScores[skill] = total / count;
    });
    return MasterySnapshot(skillScores: skillScores, skillAttempts: skillCounts);
  }

  static String skillBucketForExercise(String exerciseType) {
    switch (exerciseType) {
      case 'meaning_select':
      case 'meaning_match':
        return 'meaning';
      case 'character_select':
        return 'character';
      case 'pinyin_select':
      case 'tone_select':
        return 'pinyin_tone';
      case 'audio_select':
      case 'dictation_select':
        return 'listening';
      case 'reading_micro':
      case 'cloze_select':
      case 'order_sentence':
      case 'reply_select':
        return 'reading';
      case 'speak_read_aloud':
      case 'speak_prompted_reply':
        return 'speaking';
      default:
        return 'meaning';
    }
  }
}
