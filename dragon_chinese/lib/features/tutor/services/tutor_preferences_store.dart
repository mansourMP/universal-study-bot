import 'package:shared_preferences/shared_preferences.dart';

class TutorPreferencesStore {
  TutorPreferencesStore._();

  static const String _defaultProviderKey = 'tutor_default_provider_v1';
  static const String _voiceEnabledKey = 'tutor_voice_enabled_v1';
  static const String _voiceInputLanguageKey = 'tutor_voice_input_language_v1';

  static Future<String> getDefaultProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_defaultProviderKey) ?? 'gemini';
  }

  static Future<void> setDefaultProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_defaultProviderKey, provider);
  }

  static Future<bool> getVoiceEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_voiceEnabledKey) ?? false;
  }

  static Future<void> setVoiceEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_voiceEnabledKey, value);
  }

  static Future<String> getVoiceInputLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_voiceInputLanguageKey) ?? 'auto';
  }

  static Future<void> setVoiceInputLanguage(String language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_voiceInputLanguageKey, language);
  }
}
