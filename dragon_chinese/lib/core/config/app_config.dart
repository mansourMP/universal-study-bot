class AppConfig {
  // Start simple. Later you can switch this to --dart-define or flavors.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://interpleural-overdelicious-rodolfo.ngrok-free.dev',
  );

  static const String apiKey = String.fromEnvironment(
    'API_KEY',
    defaultValue: '',
  );

  static const String userId = String.fromEnvironment(
    'USER_ID',
    defaultValue: 'test_user_1',
  );

  // Runtime subject wiring (keeps exercise engine reusable across subjects).
  static const String targetLang = String.fromEnvironment(
    'TARGET_LANG',
    defaultValue: 'zh',
  );

  static const String subjectId = String.fromEnvironment(
    'SUBJECT_ID',
    defaultValue: 'zh',
  );

  static const String levelPrefix = String.fromEnvironment(
    'LEVEL_PREFIX',
    defaultValue: 'HSK',
  );

  // Temporary rollout control for internal model testing in AI chat.
  static const bool enableAiModelPicker = bool.fromEnvironment(
    'AI_MODEL_PICKER_ENABLED',
    defaultValue: true,
  );

  static const String aiDefaultProvider = String.fromEnvironment(
    'AI_DEFAULT_PROVIDER',
    defaultValue: 'gemini',
  );

  static String levelDisplayFromLabel(String label, int fallbackLevel) {
    final upper = label.toUpperCase();
    final stripped = upper
        .replaceAll(levelPrefix.toUpperCase(), '')
        .replaceAll('HSK', '')
        .trim();
    return stripped.isEmpty ? '$fallbackLevel' : stripped;
  }
}
