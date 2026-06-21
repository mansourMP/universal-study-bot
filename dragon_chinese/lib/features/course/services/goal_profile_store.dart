import 'package:shared_preferences/shared_preferences.dart';
import 'package:dragon_chinese/features/course/services/goal_profile.dart';

class GoalProfileStore {
  GoalProfileStore._();

  static const String _prefsKey = 'user_goal_profile_v1';

  static Future<void> setGoal(GoalType goal) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, goalId(goal));
  }

  static Future<GoalType?> getGoal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    return goalTypeFromId(raw);
  }

  static Future<GoalProfile> loadProfile() async {
    final goal = await getGoal();
    return GoalProfiles.forType(goal);
  }
}
