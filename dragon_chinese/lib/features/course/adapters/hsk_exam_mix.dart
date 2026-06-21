/// HSK exam-focused exercise mix (frontend-only; deterministic).
/// This does not change backend selection logic.
class HskExamMix {
  HskExamMix._();

  /// Stage buckets are aligned with SRS stages (0-1, 2-3, 4+).
  /// Values are relative weights for UI/UX guidance.
  static const Map<String, Map<String, double>> stageMix = {
    "0-1": {
      "flashcard": 1.6,
      "sentence_fill": 0.6,
      "collocation_pick": 0.4,
      "reading_micro": 0.2,
      "listening": 0.2,
      "speaking": 0.1,
    },
    "2-3": {
      "flashcard": 0.8,
      "sentence_fill": 1.2,
      "collocation_pick": 0.9,
      "reading_micro": 0.6,
      "listening": 0.3,
      "speaking": 0.2,
    },
    "4+": {
      "flashcard": 0.5,
      "sentence_fill": 1.0,
      "collocation_pick": 1.0,
      "reading_micro": 0.9,
      "timed_drill": 0.6,
      "listening": 0.4,
      "speaking": 0.2,
    },
  };

  /// Short label for UI disclosure.
  static const String label = "HSK Exam Mix (frontend-only)";
}
