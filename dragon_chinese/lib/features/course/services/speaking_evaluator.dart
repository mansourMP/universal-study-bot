import 'package:dragon_chinese/features/course/widgets/exercises/speaking_exercise.dart';

class SpeakingEvaluation {
  final SpeakingRating rating;
  final double score;

  const SpeakingEvaluation({required this.rating, required this.score});
}

class SpeakingEvaluator {
  static SpeakingEvaluation evaluate({
    required String transcript,
    required List<String> expectedAnswers,
    int? durationMs,
  }) {
    final heard = _normalize(transcript);
    if (heard.isEmpty) {
      return const SpeakingEvaluation(
        rating: SpeakingRating.needsWork,
        score: 0.0,
      );
    }

    final targets = expectedAnswers
        .map(_normalize)
        .where((e) => e.isNotEmpty)
        .toList();
    if (targets.isEmpty) {
      return const SpeakingEvaluation(
        rating: SpeakingRating.needsWork,
        score: 0.0,
      );
    }

    var best = 0.0;
    for (final target in targets) {
      final score = _strictSimilarity(heard, target);
      best = best > score ? best : score;
    }

    if (best >= 0.95) {
      return SpeakingEvaluation(rating: SpeakingRating.clean, score: best);
    }
    if (best >= 0.85) {
      return SpeakingEvaluation(rating: SpeakingRating.ok, score: best);
    }
    return SpeakingEvaluation(rating: SpeakingRating.needsWork, score: best);
  }

  static String _normalize(String value) {
    return _stripToneMarks(
      value.toLowerCase(),
    ).replaceAll(RegExp(r'[\s\p{P}\p{S}]', unicode: true), '').trim();
  }

  static double _strictSimilarity(String heard, String target) {
    if (heard == target) return 1.0;
    if (heard.isEmpty || target.isEmpty) return 0.0;
    final distance = _levenshtein(heard, target);
    final maxLen = heard.length > target.length ? heard.length : target.length;
    final score = (1.0 - (distance / maxLen)).clamp(0.0, 1.0);
    if (target.length <= 4) {
      // Keep short targets strict, but allow tiny STT slips.
      return score >= 0.75 ? score : 0.0;
    }
    return score;
  }

  static String _stripToneMarks(String value) {
    const map = {
      'ā': 'a',
      'á': 'a',
      'ǎ': 'a',
      'à': 'a',
      'ē': 'e',
      'é': 'e',
      'ě': 'e',
      'è': 'e',
      'ī': 'i',
      'í': 'i',
      'ǐ': 'i',
      'ì': 'i',
      'ō': 'o',
      'ó': 'o',
      'ǒ': 'o',
      'ò': 'o',
      'ū': 'u',
      'ú': 'u',
      'ǔ': 'u',
      'ù': 'u',
      'ǖ': 'v',
      'ǘ': 'v',
      'ǚ': 'v',
      'ǜ': 'v',
      'ü': 'v',
    };
    final b = StringBuffer();
    for (final rune in value.runes) {
      final ch = String.fromCharCode(rune);
      b.write(map[ch] ?? ch);
    }
    return b.toString();
  }

  static int _levenshtein(String a, String b) {
    final m = a.length;
    final n = b.length;
    final dp = List.generate(m + 1, (_) => List<int>.filled(n + 1, 0));
    for (var i = 0; i <= m; i++) {
      dp[i][0] = i;
    }
    for (var j = 0; j <= n; j++) {
      dp[0][j] = j;
    }
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        final del = dp[i - 1][j] + 1;
        final ins = dp[i][j - 1] + 1;
        final sub = dp[i - 1][j - 1] + cost;
        dp[i][j] = [del, ins, sub].reduce((x, y) => x < y ? x : y);
      }
    }
    return dp[m][n];
  }
}
