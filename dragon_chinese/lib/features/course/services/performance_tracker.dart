import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dragon_chinese/features/course/services/performance_models.dart';

class PerformanceTracker {
  static const String _prefsKey = 'performance_tracker_v1';
  final Map<String, PerformanceStat> _stats;

  PerformanceTracker(this._stats);

  static Future<PerformanceTracker> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) {
      return PerformanceTracker({});
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final stats = <String, PerformanceStat>{};
    data.forEach((key, value) {
      stats[key] = PerformanceStat.fromJson(value as Map<String, dynamic>);
    });
    return PerformanceTracker(stats);
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _stats.map((key, value) => MapEntry(key, value.toJson()));
    await prefs.setString(_prefsKey, jsonEncode(data));
  }

  void recordAttempt({
    required String skill,
    required int level,
    required bool isCorrect,
    required int latencyMs,
  }) {
    final key = '$skill:$level';
    final current = _stats[key] ?? PerformanceStat(attempts: 0, correct: 0, avgLatencyMs: 0);
    final attempts = current.attempts + 1;
    final correct = current.correct + (isCorrect ? 1 : 0);
    final alpha = 0.2;
    final avgLatency = current.attempts == 0
        ? latencyMs.toDouble()
        : (current.avgLatencyMs * (1 - alpha)) + (latencyMs * alpha);
    _stats[key] = current.copyWith(
      attempts: attempts,
      correct: correct,
      avgLatencyMs: avgLatency,
    );
  }

  PerformanceSnapshot snapshot() => PerformanceSnapshot(_stats);
}
