/// Model representing a curriculum unit with progress tracking
class Unit {
  final String id;
  final String title;
  final int unitNumber;
  final String description;
  final List<String> learningObjectives;
  final bool unlocked;
  final double progress; // 0.0 to 1.0
  final int wordCount;
  final int failingCount;

  Unit({
    required this.id,
    required this.title,
    required this.unitNumber,
    required this.description,
    required this.learningObjectives,
    required this.unlocked,
    required this.progress,
    required this.wordCount,
    required this.failingCount,
  });

  factory Unit.fromJson(Map<String, dynamic> json) {
    return Unit(
      id: json['id'] as String,
      title: json['title'] as String,
      unitNumber: json['unit_number'] as int,
      description: json['description'] as String? ?? '',
      learningObjectives:
          (json['learning_objectives'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      unlocked: json['unlocked'] as bool? ?? false,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      wordCount: json['word_count'] as int? ?? 0,
      failingCount: json['failing_count'] as int? ?? 0,
    );
  }

  /// Returns a user-friendly progress label (e.g., "40% (4/10 words)")
  String get progressLabel {
    final masteredCount = wordCount - failingCount;
    final percentage = (progress * 100).round();
    return '$percentage% ($masteredCount/$wordCount words)';
  }

  /// Returns lock status message
  String get lockMessage {
    if (unlocked) {
      return 'Unlocked';
    } else if (unitNumber == 1) {
      return 'Start here!';
    } else {
      return 'Complete Unit ${unitNumber - 1} first';
    }
  }
}
