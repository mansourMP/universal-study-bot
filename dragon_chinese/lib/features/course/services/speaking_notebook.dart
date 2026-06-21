import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SpeakingEntry {
  final int conceptId;
  final String exerciseType;
  final String rating;
  final int durationMs;
  final String? recordingPath;
  final int createdAt;
  final String? promptText;
  final List<String> sampleAnswers;

  SpeakingEntry({
    required this.conceptId,
    required this.exerciseType,
    required this.rating,
    required this.durationMs,
    required this.createdAt,
    this.recordingPath,
    this.promptText,
    required this.sampleAnswers,
  });

  Map<String, dynamic> toJson() => {
        'concept_id': conceptId,
        'exercise_type': exerciseType,
        'rating': rating,
        'duration_ms': durationMs,
        'recording_path': recordingPath,
        'created_at': createdAt,
        'prompt_text': promptText,
        'sample_answers': sampleAnswers,
      };

  factory SpeakingEntry.fromJson(Map<String, dynamic> json) {
    return SpeakingEntry(
      conceptId: json['concept_id'] ?? 0,
      exerciseType: json['exercise_type'] ?? '',
      rating: json['rating'] ?? 'ok',
      durationMs: json['duration_ms'] ?? 0,
      recordingPath: json['recording_path']?.toString(),
      createdAt: json['created_at'] ?? 0,
      promptText: json['prompt_text']?.toString(),
      sampleAnswers: (json['sample_answers'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

class SpeakingNotebook {
  static const String _prefsKey = 'speaking_notebook_v1';
  final List<SpeakingEntry> _entries;

  SpeakingNotebook(this._entries);

  static Future<SpeakingNotebook> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return SpeakingNotebook([]);
    }
    final data = jsonDecode(raw) as List<dynamic>;
    final entries = data
        .whereType<Map<String, dynamic>>()
        .map(SpeakingEntry.fromJson)
        .toList();
    return SpeakingNotebook(entries);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await prefs.setString(_prefsKey, raw);
  }

  List<SpeakingEntry> entries() => List.unmodifiable(_entries);

  void addEntry(SpeakingEntry entry) {
    _entries.insert(0, entry);
    if (_entries.length > 200) {
      _entries.removeRange(200, _entries.length);
    }
  }
}
