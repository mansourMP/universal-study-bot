import 'package:flutter/material.dart';
import 'package:dragon_chinese/features/course/models/study_session.dart';
import 'package:dragon_chinese/features/course/services/skill_service.dart';
import 'package:dragon_chinese/design_system/colors.dart';

/// Quick Study Summary Screen
/// Shows results after completing a session
class QuickStudySummaryScreen extends StatefulWidget {
  final StudySession session;
  final Map<String, double> wordScores;
  final int timeSpentSeconds;

  const QuickStudySummaryScreen({
    super.key,
    required this.session,
    required this.wordScores,
    required this.timeSpentSeconds,
  });

  @override
  State<QuickStudySummaryScreen> createState() =>
      _QuickStudySummaryScreenState();
}

class _QuickStudySummaryScreenState extends State<QuickStudySummaryScreen> {
  final SkillService _skillService = SkillService();
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    _saveSession();
  }

  Future<void> _saveSession() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      await _skillService.completeSession(
        sessionId: widget.session.sessionId,
        wordScores: widget.wordScores,
        timeSpentSeconds: widget.timeSpentSeconds,
      );
    } catch (e) {
      setState(() {
        _saveError = 'Could not save progress. Please retry.';
      });
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avgScore = widget.wordScores.values.isEmpty
        ? 0.0
        : widget.wordScores.values.reduce((a, b) => a + b) /
              widget.wordScores.length;
    final minutes = widget.timeSpentSeconds ~/ 60;
    final seconds = widget.timeSpentSeconds % 60;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Complete!'),
        backgroundColor: AppColors.primary,
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Success icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.green[100],
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check_circle,
                  size: 60,
                  color: Colors.green,
                ),
              ),
              const SizedBox(height: 32),

              // Title
              const Text(
                'Great Job!',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              // Stats card
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      _buildStatRow(
                        'Words Learned',
                        '${widget.session.wordCount}',
                        Icons.school,
                      ),
                      const Divider(height: 32),
                      _buildStatRow(
                        'Average Score',
                        '${avgScore.round()}%',
                        Icons.star,
                      ),
                      const Divider(height: 32),
                      _buildStatRow(
                        'Time Spent',
                        '$minutes:${seconds.toString().padLeft(2, '0')}',
                        Icons.timer,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),

              // Saving indicator
              if (_saving)
                const CircularProgressIndicator()
              else if (_saveError != null)
                Column(
                  children: [
                    Text(
                      _saveError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _saveSession,
                      child: const Text('Retry save'),
                    ),
                  ],
                )
              else
                const Text(
                  '✓ Progress saved',
                  style: TextStyle(
                    color: Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              const Spacer(),

              // Continue button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
                    'Continue Learning',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 32, color: AppColors.primary),
        const SizedBox(width: 16),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 16))),
        Text(
          value,
          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
