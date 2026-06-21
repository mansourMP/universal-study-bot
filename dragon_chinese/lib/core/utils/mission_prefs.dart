import 'package:shared_preferences/shared_preferences.dart';

class MissionPrefs {
  MissionPrefs._();

  static const String _key = 'mission_persona_id';

  static Future<void> setPersonaId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, id);
  }

  static Future<String?> getPersonaId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }
}
