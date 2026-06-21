import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dragon_chinese/features/course/services/mastery_models.dart';

class MasteryStore {
  static const String _prefsKey = 'word_mastery_v1';
  final Map<int, WordSkillMastery> _entries;

  MasteryStore(this._entries);

  static Future<MasteryStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return MasteryStore({});
    }
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final entries = <int, WordSkillMastery>{};
    for (final entry in json.entries) {
      final id = int.tryParse(entry.key);
      if (id == null || entry.value is! Map<String, dynamic>) continue;
      entries[id] = WordSkillMastery.fromJson(entry.value);
    }
    return MasteryStore(entries);
  }

  static MasteryStore fromData({Map<int, WordSkillMastery>? entries}) {
    return MasteryStore(entries ?? {});
  }

  WordSkillMastery masteryFor(int wordId) {
    return _entries[wordId] ??
        WordSkillMastery(wordId: wordId, skills: {});
  }

  SkillMasteryState skillStateFor(int wordId, String skill) {
    return masteryFor(wordId).skill(skill);
  }

  void updateSkill(int wordId, String skill, SkillMasteryState state) {
    final current = masteryFor(wordId);
    _entries[wordId] = current.copyWithSkill(skill, state);
  }

  List<int> get wordIds => _entries.keys.toList();

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final json = _entries.map((k, v) => MapEntry('$k', v.toJson()));
    await prefs.setString(_prefsKey, jsonEncode(json));
  }
}
