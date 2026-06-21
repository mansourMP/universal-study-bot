/// Centralized API endpoints.
/// No URL strings should exist in screens/widgets.
class Endpoints {
  // Path / Journey
  static const pathJourney = '/api/v2/path/journey';

  // Skills
  static const skillsStats = '/api/v2/skills/stats';

  // Profile
  static const profileSetup = '/api/v2/profile/setup';

  // Brain
  static const brainSummary = '/api/v2/brain/summary';
  @Deprecated('No backend route. Kept temporarily to avoid breaking imports.')
  static const brainSession = '/api/v2/brain/session';
  static const brainSubmit = '/api/v2/brain/submit';
  static const brainMission = '/api/v2/brain/mission';

  // Vocabulary
  static const vocabularyStats = '/api/v2/vocabulary/stats';
  static const vocabulary = '/api/v2/vocabulary';
  static const vocabularyWithImages = '/api/v2/vocabulary/with-images';

  // Listening
  static const listeningLevels = '/api/v2/listening/levels';
  static const listeningLessons = '/api/v2/listening/lessons';

  // Tutor
  static const tutorSuggestions = '/api/v2/tutor/suggestions';
  static const tutorChat = '/api/v2/tutor/chat';
  static const tutorHistory = '/api/v2/tutor/history';

  // Health
  static const health = '/health';
}

/// Network configuration constants.
class NetConfig {
  // Retry settings
  static const int maxRetries = 3;
  static const Duration initialBackoff = Duration(milliseconds: 300);
  static const Duration maxBackoff = Duration(milliseconds: 1500);
  static const double backoffMultiplier = 2.5;

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Retryable status codes
  static const retryableStatusCodes = {502, 503, 504};
}
