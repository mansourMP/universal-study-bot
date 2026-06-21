class ExerciseEvaluation {
  final bool isReady;
  final bool isCorrect;
  final String? feedback;
  final List<String> errors;

  const ExerciseEvaluation({
    required this.isReady,
    required this.isCorrect,
    this.feedback,
    this.errors = const [],
  });
}
