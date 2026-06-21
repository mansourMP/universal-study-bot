import 'package:dragon_chinese/features/course/services/mastery_models.dart';
import 'package:dragon_chinese/features/course/services/mastery_store.dart';

class ReadinessWeights {
  final double meaning;
  final double character;
  final double listening;
  final double reading;
  final double production;

  const ReadinessWeights({
    required this.meaning,
    required this.character,
    required this.listening,
    required this.reading,
    required this.production,
  });

  double get total => meaning + character + listening + reading + production;
}

class ReadinessBreakdown {
  final double vocab;
  final double listening;
  final double reading;
  final double production;

  const ReadinessBreakdown({
    required this.vocab,
    required this.listening,
    required this.reading,
    required this.production,
  });
}

class ReadinessScore {
  final double overall;
  final ReadinessBreakdown breakdown;
  final double attemptedCoverage;
  final double solidCoverage;

  const ReadinessScore({
    required this.overall,
    required this.breakdown,
    required this.attemptedCoverage,
    required this.solidCoverage,
  });

  int get overallRounded => overall.round();
}

class ReadinessScorer {
  final ReadinessWeights weights;

  const ReadinessScorer({
    this.weights = const ReadinessWeights(
      meaning: 0.35,
      character: 0.25,
      listening: 0.25,
      reading: 0.15,
      production: 0.0,
    ),
  });

  ReadinessScore score({
    required MasteryStore mastery,
    required List<int> conceptIds,
  }) {
    if (conceptIds.isEmpty) {
      return const ReadinessScore(
        overall: 0,
        breakdown: ReadinessBreakdown(
          vocab: 0,
          listening: 0,
          reading: 0,
          production: 0,
        ),
        attemptedCoverage: 0,
        solidCoverage: 0,
      );
    }

    double meaningSum = 0;
    double characterSum = 0;
    double listeningSum = 0;
    double readingSum = 0;
    double productionSum = 0;
    int attempted = 0;
    int solidPlus = 0;

    for (final id in conceptIds) {
      final meaning = mastery.skillStateFor(id, 'meaning');
      final character = mastery.skillStateFor(id, 'character');
      final listening = mastery.skillStateFor(id, 'listening');
      final reading = mastery.skillStateFor(id, 'reading');
      final production = mastery.skillStateFor(id, 'production');

      meaningSum += meaning.score;
      characterSum += character.score;
      listeningSum += listening.score;
      readingSum += reading.score;
      productionSum += production.score;

      if (meaning.attemptsTotal > 0 ||
          character.attemptsTotal > 0 ||
          listening.attemptsTotal > 0 ||
          reading.attemptsTotal > 0 ||
          production.attemptsTotal > 0) {
        attempted += 1;
      }
      if (meaning.stage.index >= SkillStage.solid.index &&
          character.stage.index >= SkillStage.solid.index) {
        solidPlus += 1;
      }
    }

    final count = conceptIds.length.toDouble();
    final vocabScore =
        ((meaningSum + characterSum) / (2 * count)) * 100;
    final listeningScore = (listeningSum / count) * 100;
    final readingScore = (readingSum / count) * 100;
    final productionScore = (productionSum / count) * 100;

    final overall = _weightedOverall(
      meaningSum / count,
      characterSum / count,
      listeningSum / count,
      readingSum / count,
      productionSum / count,
    ) *
        100;

    return ReadinessScore(
      overall: overall,
      breakdown: ReadinessBreakdown(
        vocab: vocabScore,
        listening: listeningScore,
        reading: readingScore,
        production: productionScore,
      ),
      attemptedCoverage: attempted / count,
      solidCoverage: solidPlus / count,
    );
  }

  double _weightedOverall(
    double meaning,
    double character,
    double listening,
    double reading,
    double production,
  ) {
    final total = weights.total;
    if (total <= 0) return 0;
    return (meaning * weights.meaning +
            character * weights.character +
            listening * weights.listening +
            reading * weights.reading +
            production * weights.production) /
        total;
  }
}
