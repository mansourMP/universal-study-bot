class LessonRoot {
  final LessonMetadata metadata;
  final List<Lesson> lessons;

  LessonRoot({required this.metadata, required this.lessons});

  factory LessonRoot.fromJson(Map<String, dynamic> json) {
    return LessonRoot(
      metadata: LessonMetadata.fromJson(json['metadata']),
      lessons: (json['lessons'] as List)
          .map((i) => Lesson.fromJson(i))
          .toList(),
    );
  }
}

class LessonMetadata {
  final String type;
  final String version;

  LessonMetadata({required this.type, required this.version});

  factory LessonMetadata.fromJson(Map<String, dynamic> json) {
    return LessonMetadata(type: json['type'], version: json['version']);
  }
}

class Lesson {
  final String lessonId;
  final String vocabUnitId;
  final String mode;
  final String skillPrimary;
  final int estimatedTimeMinutes;
  final String? status;
  final String? unlockReason;
  final Map<String, dynamic>? masterySummary;
  final LessonCultural? cultural;
  final List<LessonExercise> exerciseSequence;
  final Map<String, dynamic>? metadata;
  final String title; // Added title field

  Lesson({
    required this.lessonId,
    required this.vocabUnitId,
    required this.mode,
    required this.skillPrimary,
    required this.estimatedTimeMinutes,
    this.status,
    this.unlockReason,
    this.masterySummary,
    this.cultural,
    required this.exerciseSequence,
    this.metadata,
    this.title = '',
  });

  factory Lesson.fromJson(Map<String, dynamic> json) {
    return Lesson(
      lessonId: json['lesson_id'],
      vocabUnitId: json['vocab_unit_id'],
      mode: json['mode'],
      skillPrimary: json['skill_primary'],
      estimatedTimeMinutes: json['estimated_time_minutes'],
      status: json['status'],
      unlockReason: json['unlock_reason'],
      masterySummary: json['mastery_summary'],
      cultural: json['cultural'] != null
          ? LessonCultural.fromJson(json['cultural'])
          : null,
      exerciseSequence: (json['exercise_sequence'] as List)
          .map((i) => LessonExercise.fromJson(i))
          .toList(),
      metadata: json['metadata'],
      title: json['title'] ?? '',
    );
  }
}

class LessonCultural {
  final String guideCharacter;
  final String setting;
  final String storyContext;
  final String languageObjective;

  LessonCultural({
    required this.guideCharacter,
    required this.setting,
    required this.storyContext,
    required this.languageObjective,
  });

  factory LessonCultural.fromJson(Map<String, dynamic> json) {
    return LessonCultural(
      guideCharacter: json['guide_character'],
      setting: json['setting'],
      storyContext: json['story_context'],
      languageObjective: json['language_objective'],
    );
  }
}

class LessonExercise {
  final String exerciseId;
  final String type;
  final String instructionZh;
  final String instructionEn;

  // Optional dynamic fields for activities
  final String? answer;
  final List<String>? options;
  final String? contextSentence;
  final List<String>? wordBank;
  final List<String>? optionImages; // New field for image URLs

  LessonExercise({
    required this.exerciseId,
    required this.type,
    required this.instructionZh,
    required this.instructionEn,
    this.answer,
    this.options,
    this.contextSentence,
    this.wordBank,
    this.optionImages,
  });

  factory LessonExercise.fromJson(Map<String, dynamic> json) {
    return LessonExercise(
      exerciseId: json['exercise_id'],
      type: json['type'],
      instructionZh: json['instruction_zh'],
      instructionEn: json['instruction_en'],
      answer: json['answer'],
      options: json['options'] != null
          ? List<String>.from(json['options'])
          : null,
      contextSentence: json['context_sentence'],
      wordBank: json['word_bank'] != null
          ? List<String>.from(json['word_bank'])
          : null,
      optionImages: json['option_images'] != null
          ? List<String>.from(json['option_images'])
          : null,
    );
  }
}
