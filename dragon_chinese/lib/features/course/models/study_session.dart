/// Quick Study Session Models
/// Represents a batch learning session with 5-10 words
class StudySession {
  final String sessionId;
  final String unitId;
  final String unitTitle;
  final String unitDescription;
  final int wordCount;
  final List<SessionWord> words;
  final List<SessionExercise> exercises;

  StudySession({
    required this.sessionId,
    required this.unitId,
    required this.unitTitle,
    required this.unitDescription,
    required this.wordCount,
    required this.words,
    required this.exercises,
  });

  factory StudySession.fromJson(Map<String, dynamic> json) {
    return StudySession(
      sessionId: json['session_id'] as String,
      unitId: json['unit_id'] as String,
      unitTitle: json['unit_title'] as String,
      unitDescription: json['unit_description'] as String,
      wordCount: json['word_count'] as int,
      words: (json['words'] as List)
          .map((w) => SessionWord.fromJson(w as Map<String, dynamic>))
          .toList(),
      exercises: (json['exercises'] as List)
          .map((e) => SessionExercise.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Represents a single word in the session
class SessionWord {
  final String wordId;
  final String headword;
  final String pronunciation;
  final String translation;
  final String exampleSentence;

  SessionWord({
    required this.wordId,
    required this.headword,
    required this.pronunciation,
    required this.translation,
    required this.exampleSentence,
  });

  factory SessionWord.fromJson(Map<String, dynamic> json) {
    return SessionWord(
      wordId: json['word_id'] as String,
      headword: json['headword'] as String,
      pronunciation: json['pronunciation'] as String,
      translation: json['translation'] as String,
      exampleSentence: json['example_sentence'] as String? ?? '',
    );
  }
}

/// Represents a batch exercise in the session
class SessionExercise {
  final String exerciseId;
  final String type;
  final String instruction;
  final List<String> wordIds;
  final Map<String, dynamic> data;

  SessionExercise({
    required this.exerciseId,
    required this.type,
    required this.instruction,
    required this.wordIds,
    required this.data,
  });

  factory SessionExercise.fromJson(Map<String, dynamic> json) {
    return SessionExercise(
      exerciseId: json['exercise_id'] as String,
      type: json['type'] as String,
      instruction: json['instruction'] as String,
      wordIds: (json['word_ids'] as List).cast<String>(),
      data: json,
    );
  }

  // Helper getters for specific exercise types
  List<MatchPair>? get pairs {
    if (type == 'match_pairs' && data.containsKey('pairs')) {
      return (data['pairs'] as List)
          .map((p) => MatchPair.fromJson(p as Map<String, dynamic>))
          .toList();
    }
    return null;
  }

  List<MultipleChoiceQuestion>? get questions {
    if (type == 'multiple_choice' && data.containsKey('questions')) {
      return (data['questions'] as List)
          .map(
            (q) => MultipleChoiceQuestion.fromJson(q as Map<String, dynamic>),
          )
          .toList();
    }
    return null;
  }
}

/// Match pairs exercise data
class MatchPair {
  final String chinese;
  final String english;
  final String wordId;

  MatchPair({
    required this.chinese,
    required this.english,
    required this.wordId,
  });

  factory MatchPair.fromJson(Map<String, dynamic> json) {
    return MatchPair(
      chinese: json['chinese'] as String,
      english: json['english'] as String,
      wordId: json['word_id'] as String,
    );
  }
}

/// Multiple choice question data
class MultipleChoiceQuestion {
  final String wordId;
  final String question;
  final List<String> options;
  final String correctAnswer;

  MultipleChoiceQuestion({
    required this.wordId,
    required this.question,
    required this.options,
    required this.correctAnswer,
  });

  factory MultipleChoiceQuestion.fromJson(Map<String, dynamic> json) {
    return MultipleChoiceQuestion(
      wordId: json['word_id'] as String,
      question: json['question'] as String,
      options: (json['options'] as List).cast<String>(),
      correctAnswer: json['correct_answer'] as String,
    );
  }
}
