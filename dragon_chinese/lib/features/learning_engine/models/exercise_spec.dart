class ExerciseSpec {
  final String exerciseId;
  final String subjectId;
  final String templateId;
  final String promptText;
  final List<String> choices;
  final int? answerIndex;
  final List<String> answerTokens;
  final Map<String, dynamic> payload;

  const ExerciseSpec({
    required this.exerciseId,
    required this.subjectId,
    required this.templateId,
    required this.promptText,
    this.choices = const [],
    this.answerIndex,
    this.answerTokens = const [],
    this.payload = const {},
  });
}
