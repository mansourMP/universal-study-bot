import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/services/mastery_models.dart';
import 'package:dragon_chinese/features/course/services/mastery_store.dart';
import 'package:dragon_chinese/features/course/services/readiness_scorer.dart';

void main() {
  test('ReadinessScore computes deterministic overall', () {
    final mastery = MasteryStore.fromData(
      entries: {
        1: WordSkillMastery(
          wordId: 1,
          skills: {
            'meaning': SkillMasteryState.initial().copyWith(score: 0.8),
            'character': SkillMasteryState.initial().copyWith(score: 0.7),
            'listening': SkillMasteryState.initial().copyWith(score: 0.6),
            'reading': SkillMasteryState.initial().copyWith(score: 0.5),
            'production': SkillMasteryState.initial().copyWith(score: 0.2),
          },
        ),
        2: WordSkillMastery(
          wordId: 2,
          skills: {
            'meaning': SkillMasteryState.initial().copyWith(score: 0.4),
            'character': SkillMasteryState.initial().copyWith(score: 0.5),
            'listening': SkillMasteryState.initial().copyWith(score: 0.4),
            'reading': SkillMasteryState.initial().copyWith(score: 0.3),
            'production': SkillMasteryState.initial().copyWith(score: 0.1),
          },
        ),
      },
    );
    const scorer = ReadinessScorer();
    final score = scorer.score(mastery: mastery, conceptIds: const [1, 2]);
    expect(score.overall, greaterThan(0));
    expect(score.breakdown.vocab, greaterThan(0));
    expect(score.breakdown.listening, greaterThan(0));
    expect(score.breakdown.reading, greaterThan(0));
    print('Readiness overall: ${score.overall.toStringAsFixed(1)}');
  });
}
