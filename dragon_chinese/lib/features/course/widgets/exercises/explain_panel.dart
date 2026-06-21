import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/exercise_theme.dart';
import 'package:dragon_chinese/features/course/models/pilot_exercise_pack.dart';

class ExplainButton extends StatelessWidget {
  final PilotWhy? why;

  const ExplainButton({super.key, required this.why});

  @override
  Widget build(BuildContext context) {
    if (why == null) return const SizedBox.shrink();
    return IconButton(
      onPressed: () => showExplain(context, why!),
      icon: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ExerciseThemeTokens.textMuted),
        ),
        child: const Icon(Icons.question_mark_rounded, size: 14, color: ExerciseThemeTokens.textSecondary),
      ),
      tooltip: 'Why this exercise?',
    );
  }

  static void showExplain(BuildContext context, PilotWhy why) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ExerciseThemeTokens.transparent, // Use container decoration
      isScrollControlled: true,
      builder: (context) => _ExplainSheet(why: why),
    );
  }
}

class _ExplainSheet extends StatelessWidget {
  final PilotWhy why;

  const _ExplainSheet({required this.why});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ExerciseThemeTokens.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.psychology_outlined, color: ExerciseThemeTokens.accent),
                const SizedBox(width: 12),
                const Text('Why this exercise?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                )
              ],
            ),
            const Divider(height: 32),
            _buildReasonSection(),
            if (why.signals.accuracy != null || why.signals.mistakeCount != null) ...[
              const SizedBox(height: 24),
              _buildStatsSection(),
            ],
            const SizedBox(height: 24),
            _buildFooterNote(),
          ],
        ),
      ),
    );
  }

  Widget _buildReasonSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REASON',
          style: ExerciseThemeTokens.caption.copyWith(letterSpacing: 1),
        ),
        const SizedBox(height: 8),
        ...why.reasons.map((r) => Text(r, style: ExerciseThemeTokens.promptBody)),
      ],
    );
  }

  Widget _buildStatsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ExerciseThemeTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          if (why.signals.accuracy != null)
            _stat('Accuracy', '${(why.signals.accuracy! * 100).round()}%'),
          if (why.signals.mistakeCount != null)
            _stat('Mistakes', '${why.signals.mistakeCount}'),
          if (why.signals.skillTarget != null)
            _stat('Skill', why.signals.skillTarget!.toUpperCase()),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ExerciseThemeTokens.textPrimary)),
        Text(label, style: ExerciseThemeTokens.caption),
      ],
    );
  }

  Widget _buildFooterNote() {
    return Center(
      child: Text(
        'Deterministic path. No randomization.',
        style: ExerciseThemeTokens.caption.copyWith(color: ExerciseThemeTokens.textMuted),
      ),
    );
  }
}