import 'package:flutter/services.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';

class PilotExercisePackLoader {
  static const String assetPath = 'assets/pilot/hsk1_exercises_v1.json';

  Future<PilotExercisePack> loadPack() async {
    final raw = await rootBundle.loadString(assetPath);
    return PilotExercisePack.fromRawJson(raw);
  }
}
