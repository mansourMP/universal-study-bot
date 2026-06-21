import 'package:flutter_test/flutter_test.dart';
import 'package:dragon_chinese/features/course/services/mastery_models.dart';
import 'package:dragon_chinese/features/course/services/mastery_updater.dart';

void main() {
  test('MasteryUpdater increases score on correct first try', () {
    final now = 1_700_000_000_000;
    final current = SkillMasteryState.initial();
    final next = MasteryUpdater.applyAttempt(
      current: current,
      skill: 'meaning',
      isCorrect: true,
      attemptsUsed: 1,
      durationMs: 1500,
      now: now,
    );
    expect(next.score, greaterThan(current.score));
    expect(next.dueAt, greaterThan(now));
    expect(next.lastResult, true);
  });

  test('MasteryUpdater decreases score on wrong', () {
    final now = 1_700_000_000_000;
    final current = SkillMasteryState.initial().copyWith(score: 0.6);
    final next = MasteryUpdater.applyAttempt(
      current: current,
      skill: 'reading',
      isCorrect: false,
      attemptsUsed: 1,
      durationMs: 2500,
      now: now,
    );
    expect(next.score, lessThan(current.score));
    expect(next.dueAt, greaterThan(now));
    expect(next.stage, isNot(SkillStage.mastered));
  });

  test('MasteryUpdater produces deterministic output for same inputs', () {
    final now = 1_700_000_000_000;
    final current = SkillMasteryState.initial().copyWith(score: 0.5);

    final next1 = MasteryUpdater.applyAttempt(
      current: current,
      skill: 'character',
      isCorrect: true,
      attemptsUsed: 2,
      durationMs: 2000,
      now: now,
    );
    final next2 = MasteryUpdater.applyAttempt(
      current: current,
      skill: 'character',
      isCorrect: true,
      attemptsUsed: 2,
      durationMs: 2000,
      now: now,
    );

    expect(next1.score, next2.score);
    expect(next1.dueAt, next2.dueAt);
    expect(next1.stage, next2.stage);
  });

  test('MasteryUpdater stage transitions correctly', () {
    final now = 1_700_000_000_000;

    // newStage -> learning
    final state1 = SkillMasteryState.initial().copyWith(score: 0.3);
    final next1 = MasteryUpdater.applyAttempt(
      current: state1,
      skill: 'listening',
      isCorrect: true,
      attemptsUsed: 1,
      durationMs: 1200,
      now: now,
    );
    expect(next1.stage, SkillStage.learning);

    // learning -> solid
    final state2 = SkillMasteryState.initial().copyWith(score: 0.55);
    final next2 = MasteryUpdater.applyAttempt(
      current: state2,
      skill: 'production',
      isCorrect: true,
      attemptsUsed: 1,
      durationMs: 1500,
      now: now,
    );
    expect(next2.stage, SkillStage.solid);

    // solid -> mastered
    final state3 = SkillMasteryState.initial().copyWith(score: 0.75);
    final next3 = MasteryUpdater.applyAttempt(
      current: state3,
      skill: 'meaning',
      isCorrect: true,
      attemptsUsed: 1,
      durationMs: 1000,
      now: now,
    );
    expect(next3.stage, SkillStage.mastered);
  });

  test('MasteryUpdater applies different intervals per skill', () {
    final now = 1_700_000_000_000;
    final current = SkillMasteryState.initial().copyWith(score: 0.5);

    final meaningNext = MasteryUpdater.applyAttempt(
      current: current,
      skill: 'meaning',
      isCorrect: true,
      attemptsUsed: 1,
      durationMs: 1500,
      now: now,
    );
    final readingNext = MasteryUpdater.applyAttempt(
      current: current,
      skill: 'reading',
      isCorrect: true,
      attemptsUsed: 1,
      durationMs: 1500,
      now: now,
    );

    // Reading has longer base interval than meaning
    expect(readingNext.dueAt, greaterThan(meaningNext.dueAt));
  });
}
