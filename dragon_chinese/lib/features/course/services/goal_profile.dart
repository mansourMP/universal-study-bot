enum GoalType { exam, speaking, professional, travel, casual }

class GoalConstraints {
  final bool writingEnabled;
  final int maxReadingMicroPerSession;
  final int minSpeakingPerSession;
  final int maxNewWordsPerSession;

  const GoalConstraints({
    required this.writingEnabled,
    required this.maxReadingMicroPerSession,
    required this.minSpeakingPerSession,
    required this.maxNewWordsPerSession,
  });
}

class GoalProfile {
  final GoalType goal;
  final String label;
  final Map<String, double> skillWeights;
  final Map<String, double> exerciseTypeWeights;
  final List<String> contextTemplates;
  final GoalConstraints constraints;

  const GoalProfile({
    required this.goal,
    required this.label,
    required this.skillWeights,
    required this.exerciseTypeWeights,
    required this.contextTemplates,
    required this.constraints,
  });
}

class GoalProfiles {
  GoalProfiles._();

  static const GoalProfile exam = GoalProfile(
    goal: GoalType.exam,
    label: 'Exam Focus',
    skillWeights: {
      'meaning': 0.24,
      'characters': 0.20,
      'pinyin': 0.12,
      'listening': 0.16,
      'reading': 0.22,
      'production': 0.06,
    },
    exerciseTypeWeights: {
      'meaning_select': 0.20,
      'meaning_match': 0.15,
      'character_select': 0.12,
      'order_sentence': 0.08,
      'pinyin_select': 0.08,
      'dictation_select': 0.12,
      'audio_select': 0.10,
      'cloze_select': 0.15,
      'reading_micro': 0.18,
      'reply_select': 0.03,
      'speak_prompted_reply': 0.02,
      'speak_read_aloud': 0.02,
    },
    contextTemplates: [
      'Exam focus: choose the best completion.',
      'Test-ready: identify the correct usage of {word}.',
      'HSK practice: focus on {unit}.',
    ],
    constraints: GoalConstraints(
      writingEnabled: true,
      maxReadingMicroPerSession: 3,
      minSpeakingPerSession: 0,
      maxNewWordsPerSession: 6,
    ),
  );

  static const GoalProfile speaking = GoalProfile(
    goal: GoalType.speaking,
    label: 'Speaking Focus',
    skillWeights: {
      'meaning': 0.14,
      'characters': 0.10,
      'pinyin': 0.16,
      'listening': 0.22,
      'reading': 0.10,
      'production': 0.28,
    },
    exerciseTypeWeights: {
      'meaning_select': 0.10,
      'meaning_match': 0.08,
      'character_select': 0.08,
      'order_sentence': 0.06,
      'pinyin_select': 0.12,
      'dictation_select': 0.14,
      'audio_select': 0.18,
      'cloze_select': 0.06,
      'reading_micro': 0.06,
      'reply_select': 0.16,
      'speak_prompted_reply': 0.20,
      'speak_read_aloud': 0.18,
    },
    contextTemplates: [
      'Say this naturally in a short reply.',
      'In a quick conversation, use {word}.',
      'Practice speaking about {unit}.',
    ],
    constraints: GoalConstraints(
      writingEnabled: false,
      maxReadingMicroPerSession: 1,
      minSpeakingPerSession: 3,
      maxNewWordsPerSession: 5,
    ),
  );

  static const GoalProfile professional = GoalProfile(
    goal: GoalType.professional,
    label: 'Professional Focus',
    skillWeights: {
      'meaning': 0.18,
      'characters': 0.14,
      'pinyin': 0.10,
      'listening': 0.20,
      'reading': 0.24,
      'production': 0.14,
    },
    exerciseTypeWeights: {
      'meaning_select': 0.14,
      'meaning_match': 0.12,
      'character_select': 0.10,
      'order_sentence': 0.10,
      'pinyin_select': 0.06,
      'dictation_select': 0.10,
      'audio_select': 0.14,
      'cloze_select': 0.14,
      'reading_micro': 0.18,
      'reply_select': 0.12,
      'speak_prompted_reply': 0.12,
      'speak_read_aloud': 0.08,
    },
    contextTemplates: [
      'In a meeting, use {word}.',
      'Professional tone: apply {unit}.',
      'Workplace context: choose the best option.',
    ],
    constraints: GoalConstraints(
      writingEnabled: true,
      maxReadingMicroPerSession: 3,
      minSpeakingPerSession: 1,
      maxNewWordsPerSession: 6,
    ),
  );

  static const GoalProfile travel = GoalProfile(
    goal: GoalType.travel,
    label: 'Travel Focus',
    skillWeights: {
      'meaning': 0.18,
      'characters': 0.12,
      'pinyin': 0.14,
      'listening': 0.22,
      'reading': 0.12,
      'production': 0.22,
    },
    exerciseTypeWeights: {
      'meaning_select': 0.14,
      'meaning_match': 0.10,
      'character_select': 0.10,
      'order_sentence': 0.08,
      'pinyin_select': 0.10,
      'dictation_select': 0.14,
      'audio_select': 0.18,
      'cloze_select': 0.08,
      'reading_micro': 0.08,
      'reply_select': 0.14,
      'speak_prompted_reply': 0.16,
      'speak_read_aloud': 0.12,
    },
    contextTemplates: [
      'At the station, you hear: {word}.',
      'While traveling, use {unit} phrases.',
      'Travel context: choose the best response.',
    ],
    constraints: GoalConstraints(
      writingEnabled: true,
      maxReadingMicroPerSession: 2,
      minSpeakingPerSession: 2,
      maxNewWordsPerSession: 6,
    ),
  );

  static const GoalProfile casual = GoalProfile(
    goal: GoalType.casual,
    label: 'Casual Focus',
    skillWeights: {
      'meaning': 0.20,
      'characters': 0.18,
      'pinyin': 0.12,
      'listening': 0.18,
      'reading': 0.16,
      'production': 0.16,
    },
    exerciseTypeWeights: {
      'meaning_select': 0.16,
      'meaning_match': 0.12,
      'character_select': 0.12,
      'order_sentence': 0.10,
      'pinyin_select': 0.10,
      'dictation_select': 0.10,
      'audio_select': 0.12,
      'cloze_select': 0.12,
      'reading_micro': 0.12,
      'reply_select': 0.10,
      'speak_prompted_reply': 0.10,
      'speak_read_aloud': 0.08,
    },
    contextTemplates: [
      'Chat with a friend: use {word}.',
      'Everyday context: focus on {unit}.',
      'Casual talk: choose the best fit.',
    ],
    constraints: GoalConstraints(
      writingEnabled: true,
      maxReadingMicroPerSession: 2,
      minSpeakingPerSession: 1,
      maxNewWordsPerSession: 6,
    ),
  );

  static const GoalProfile defaultProfile = casual;

  static GoalProfile forType(GoalType? goal) {
    switch (goal) {
      case GoalType.exam:
        return exam;
      case GoalType.speaking:
        return speaking;
      case GoalType.professional:
        return professional;
      case GoalType.travel:
        return travel;
      case GoalType.casual:
      default:
        return defaultProfile;
    }
  }
}

String goalId(GoalType goal) => goal.name;

GoalType? goalTypeFromId(String? id) {
  if (id == null) return null;
  for (final value in GoalType.values) {
    if (value.name == id) return value;
  }
  return null;
}

String goalLabel(GoalType? goal) {
  return GoalProfiles.forType(goal).label;
}
