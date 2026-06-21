import 'package:dragon_chinese/features/course/services/skill_service.dart';

class ImageMatchingController {
  final SkillService _skills;
  ImageMatchingController({SkillService? skills})
      : _skills = skills ?? SkillService();

  Future<List<VocabularyWord>> loadWords(
    int level,
    String sourceLang, {
    String? targetLang,
  }) {
    return _skills.fetchImageVocabulary(
      level,
      sourceLang: sourceLang,
      targetLang: targetLang,
    );
  }
}
