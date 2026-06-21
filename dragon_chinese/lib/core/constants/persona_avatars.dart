class PersonaAvatars {
  PersonaAvatars._();

  static const String defaultAssistant = 'assets/images/people/profile_mentor_01.png';

  static const Map<String, String> missionPersonaAsset = {
    'hsk': 'assets/images/people/persona_hsk.png',
    'casual': 'assets/images/people/persona_casual.png',
    'professional': 'assets/images/people/persona_professional.png',
    'survival': 'assets/images/people/persona_survival.png',
    'cultural': 'assets/images/people/persona_cultural.png',
    'digital': 'assets/images/people/persona_digital.png',
  };

  static const Map<String, String> profileAsset = {
    'mentor_01': 'assets/images/people/profile_mentor_01.png',
    'creator_01': 'assets/images/people/profile_creator_01.png',
    'artist_01': 'assets/images/people/profile_artist_01.png',
  };

  static String mission(String? personaId) {
    if (personaId == null) return defaultAssistant;
    return missionPersonaAsset[personaId] ?? defaultAssistant;
  }
}
