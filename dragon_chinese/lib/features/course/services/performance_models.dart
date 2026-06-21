class PerformanceStat {
  final int attempts;
  final int correct;
  final double avgLatencyMs;

  PerformanceStat({
    required this.attempts,
    required this.correct,
    required this.avgLatencyMs,
  });

  PerformanceStat copyWith({int? attempts, int? correct, double? avgLatencyMs}) {
    return PerformanceStat(
      attempts: attempts ?? this.attempts,
      correct: correct ?? this.correct,
      avgLatencyMs: avgLatencyMs ?? this.avgLatencyMs,
    );
  }

  Map<String, dynamic> toJson() => {
        'attempts': attempts,
        'correct': correct,
        'avgLatencyMs': avgLatencyMs,
      };

  factory PerformanceStat.fromJson(Map<String, dynamic> json) {
    return PerformanceStat(
      attempts: json['attempts'] ?? 0,
      correct: json['correct'] ?? 0,
      avgLatencyMs: (json['avgLatencyMs'] is num)
          ? (json['avgLatencyMs'] as num).toDouble()
          : 0.0,
    );
  }
}

class PerformanceSnapshot {
  final Map<String, PerformanceStat> stats;

  PerformanceSnapshot(this.stats);

  double accuracy(String skill, int level) {
    final stat = stats['$skill:$level'];
    if (stat == null || stat.attempts == 0) return 0.0;
    return stat.correct / stat.attempts;
  }

  double latency(String skill, int level) {
    final stat = stats['$skill:$level'];
    return stat?.avgLatencyMs ?? 0.0;
  }
}
