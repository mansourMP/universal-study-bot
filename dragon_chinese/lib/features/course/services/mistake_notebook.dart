import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dragon_chinese/features/course/services/mistake_stats.dart';

class MistakeEntry {
  final int conceptId;
  final String exerciseType;
  final int wrongCount;
  final int streak;
  final int lastWrongAt;

  MistakeEntry({
    required this.conceptId,
    required this.exerciseType,
    required this.wrongCount,
    required this.streak,
    required this.lastWrongAt,
  });

  MistakeEntry copyWith({int? wrongCount, int? streak, int? lastWrongAt}) {
    return MistakeEntry(
      conceptId: conceptId,
      exerciseType: exerciseType,
      wrongCount: wrongCount ?? this.wrongCount,
      streak: streak ?? this.streak,
      lastWrongAt: lastWrongAt ?? this.lastWrongAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'concept_id': conceptId,
        'exercise_type': exerciseType,
        'wrong_count': wrongCount,
        'streak': streak,
        'last_wrong_at': lastWrongAt,
      };

  factory MistakeEntry.fromJson(Map<String, dynamic> json) {
    return MistakeEntry(
      conceptId: json['concept_id'] ?? 0,
      exerciseType: json['exercise_type'] ?? '',
      wrongCount: json['wrong_count'] ?? 0,
      streak: json['streak'] ?? 0,
      lastWrongAt: json['last_wrong_at'] ?? 0,
    );
  }
}

class MistakeNotebook {
  static const String _prefsKey = 'mistake_notebook_v1';
  final Map<String, MistakeEntry> _entries;

  MistakeNotebook(this._entries);

  static Future<MistakeNotebook> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return MistakeNotebook({});
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final entries = <String, MistakeEntry>{};
    data.forEach((key, value) {
      entries[key] = MistakeEntry.fromJson(value as Map<String, dynamic>);
    });
    return MistakeNotebook(entries);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _entries.map((key, value) => MapEntry(key, value.toJson()));
    await prefs.setString(_prefsKey, jsonEncode(data));
  }

  void recordAttempt({required int conceptId, required String exerciseType, required bool isCorrect}) {
    final key = _key(conceptId, exerciseType);
    final existing = _entries[key];
    if (isCorrect) {
      if (existing != null) {
        _entries[key] = existing.copyWith(streak: 0);
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final updated = (existing ??
            MistakeEntry(
              conceptId: conceptId,
              exerciseType: exerciseType,
              wrongCount: 0,
              streak: 0,
              lastWrongAt: 0,
            ))
        .copyWith(
          wrongCount: (existing?.wrongCount ?? 0) + 1,
          streak: (existing?.streak ?? 0) + 1,
          lastWrongAt: now,
        );
    _entries[key] = updated;
  }

  List<MistakeEntry> weakest(int limit) {
    final list = _entries.values.toList();
    list.sort((a, b) {
      final score = b.wrongCount.compareTo(a.wrongCount);
      if (score != 0) return score;
      return b.lastWrongAt.compareTo(a.lastWrongAt);
    });
    return list.take(limit).toList();
  }

  List<MistakeEntry> streaks() {
    final list = _entries.values.where((e) => e.streak > 0).toList();
    list.sort((a, b) => b.streak.compareTo(a.streak));
    return list;
  }

  MistakeStats stats() {
    final counts = <String, int>{};
    for (final entry in _entries.values) {
      counts[entry.exerciseType] =
          (counts[entry.exerciseType] ?? 0) + entry.wrongCount;
    }
    return MistakeStats(typeWrongCount: counts);
  }

  String _key(int conceptId, String type) => '$type:$conceptId';
}
