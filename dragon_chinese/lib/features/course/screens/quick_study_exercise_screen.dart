import 'package:flutter/material.dart';
import 'package:dragon_chinese/features/course/models/study_session.dart';
import 'package:dragon_chinese/design_system/colors.dart';

/// Quick Study Exercise Screen
/// Shows batch exercises for all words in the session
class QuickStudyExerciseScreen extends StatefulWidget {
  final StudySession session;

  const QuickStudyExerciseScreen({super.key, required this.session});

  @override
  State<QuickStudyExerciseScreen> createState() =>
      _QuickStudyExerciseScreenState();
}

class _QuickStudyExerciseScreenState extends State<QuickStudyExerciseScreen> {
  int _currentExerciseIndex = 0;
  final Map<String, double> _wordScores = {};
  final Map<String, double> _wordScoreTotals = {};
  final Map<String, int> _wordScoreCounts = {};
  final Map<String, SessionWord> _sessionWordsById = {};
  final Map<String, Map<String, String>> _pairSelectionsByExercise = {};
  final Map<String, List<String>> _pairOptionsByExercise = {};
  final Map<String, Map<String, String>> _mcSelectionsByExercise = {};
  final Map<String, Map<String, String>> _pinyinInputsByExercise = {};
  final DateTime _startTime = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Initialize scores to 0
    for (var word in widget.session.words) {
      _wordScores[word.wordId] = 0.0;
      _wordScoreTotals[word.wordId] = 0.0;
      _wordScoreCounts[word.wordId] = 0;
      _sessionWordsById[word.wordId] = word;
    }
  }

  void _recordWordScore(String wordId, double score) {
    final currentTotal = _wordScoreTotals[wordId] ?? 0.0;
    final currentCount = _wordScoreCounts[wordId] ?? 0;
    final nextTotal = currentTotal + score;
    final nextCount = currentCount + 1;
    _wordScoreTotals[wordId] = nextTotal;
    _wordScoreCounts[wordId] = nextCount;
    _wordScores[wordId] = nextTotal / nextCount;
  }

  String _normalizePinyin(String value) {
    final trimmed = value.trim().toLowerCase();
    if (trimmed.isEmpty) return '';
    const toneMap = <String, String>{
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
    final normalized = StringBuffer();
    for (final rune in trimmed.runes) {
      final ch = String.fromCharCode(rune);
      normalized.write(toneMap[ch] ?? ch);
    }
    return normalized.toString().replaceAll(RegExp(r'\s+'), ' ');
  }

  void _completeExercise() {
    if (_currentExerciseIndex < widget.session.exercises.length - 1) {
      setState(() {
        _currentExerciseIndex++;
      });
    } else {
      // All exercises complete, navigate to summary
      final timeSpent = DateTime.now().difference(_startTime).inSeconds;
      Navigator.pushReplacementNamed(
        context,
        '/quick-study-summary',
        arguments: {
          'session': widget.session,
          'scores': _wordScores,
          'timeSpent': timeSpent,
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final exercise = widget.session.exercises[_currentExerciseIndex];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Practice ${_currentExerciseIndex + 1}/${widget.session.exercises.length}',
        ),
        backgroundColor: AppColors.primary,
      ),
      body: Column(
        children: [
          // Progress bar
          LinearProgressIndicator(
            value:
                (_currentExerciseIndex + 1) / widget.session.exercises.length,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),

          // Exercise content
          Expanded(child: _buildExerciseContent(exercise)),
        ],
      ),
    );
  }

  Widget _buildExerciseContent(SessionExercise exercise) {
    switch (exercise.type) {
      case 'match_pairs':
        return _buildMatchPairsExercise(exercise);
      case 'multiple_choice':
        return _buildMultipleChoiceExercise(exercise);
      case 'type_pinyin':
        return _buildTypePinyinExercise(exercise);
      default:
        return Center(child: Text('Unknown exercise type: ${exercise.type}'));
    }
  }

  Widget _buildMatchPairsExercise(SessionExercise exercise) {
    final pairs = exercise.pairs ?? [];
    final options = _pairOptionsByExercise.putIfAbsent(exercise.exerciseId, () {
      final values = pairs.map((p) => p.english).toList();
      values.shuffle();
      return values;
    });
    final selections = _pairSelectionsByExercise.putIfAbsent(
      exercise.exerciseId,
      () => {},
    );

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            exercise.instruction,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: pairs.length,
              itemBuilder: (context, index) {
                final pair = pairs[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pair.chinese,
                          style: const TextStyle(fontSize: 24),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: selections[pair.wordId],
                          items: options
                              .map(
                                (option) => DropdownMenuItem<String>(
                                  value: option,
                                  child: Text(option),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            setState(() {
                              if (value != null) {
                                selections[pair.wordId] = value;
                              }
                            });
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Select meaning',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          ElevatedButton(
            onPressed: selections.length == pairs.length
                ? () {
                    for (var pair in pairs) {
                      final isCorrect = selections[pair.wordId] == pair.english;
                      _recordWordScore(pair.wordId, isCorrect ? 100.0 : 0.0);
                    }
                    _completeExercise();
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultipleChoiceExercise(SessionExercise exercise) {
    final questions = exercise.questions ?? [];
    final selections = _mcSelectionsByExercise.putIfAbsent(
      exercise.exerciseId,
      () => {},
    );

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            exercise.instruction,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.builder(
              itemCount: questions.length,
              itemBuilder: (context, index) {
                final question = questions[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 24),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          question.question,
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        ...question.options.map(
                          (option) => Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: OutlinedButton(
                              onPressed: () {
                                setState(() {
                                  selections[question.wordId] = option;
                                });
                              },
                              style: OutlinedButton.styleFrom(
                                backgroundColor:
                                    selections[question.wordId] == option
                                    ? AppColors.primary.withOpacity(0.08)
                                    : null,
                                padding: const EdgeInsets.all(16),
                              ),
                              child: Text(
                                option,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          ElevatedButton(
            onPressed: selections.length == questions.length
                ? () {
                    for (var question in questions) {
                      final selected = selections[question.wordId];
                      final isCorrect = selected == question.correctAnswer;
                      _recordWordScore(
                        question.wordId,
                        isCorrect ? 100.0 : 0.0,
                      );
                    }
                    _completeExercise();
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypePinyinExercise(SessionExercise exercise) {
    final inputs = _pinyinInputsByExercise.putIfAbsent(
      exercise.exerciseId,
      () => {},
    );
    final words = exercise.wordIds
        .map((id) => _sessionWordsById[id])
        .whereType<SessionWord>()
        .toList();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            exercise.instruction,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: ListView.separated(
              itemCount: words.length,
              separatorBuilder: (_, _) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                final word = words[index];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          word.headword,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          word.translation,
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          initialValue: inputs[word.wordId],
                          onChanged: (value) {
                            setState(() {
                              inputs[word.wordId] = value;
                            });
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            labelText: 'Type pinyin',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          ElevatedButton(
            onPressed: words.isNotEmpty && inputs.length == words.length
                ? () {
                    for (var word in words) {
                      final typed = _normalizePinyin(inputs[word.wordId] ?? '');
                      final expected = _normalizePinyin(word.pronunciation);
                      final isCorrect = typed == expected && typed.isNotEmpty;
                      _recordWordScore(word.wordId, isCorrect ? 100.0 : 0.0);
                    }
                    _completeExercise();
                  }
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: const Text(
              'Continue',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
