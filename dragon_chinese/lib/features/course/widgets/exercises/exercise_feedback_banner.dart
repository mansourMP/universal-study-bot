import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/exercise_theme.dart';

enum ExerciseFeedbackTone { success, error, info, neutral }

class ExerciseFeedbackBanner extends StatelessWidget {
  final ExerciseFeedbackTone tone;
  final IconData? icon;
  final String title;
  final String? body;
  final List<String> details;
  final EdgeInsetsGeometry padding;

  const ExerciseFeedbackBanner({
    super.key,
    required this.tone,
    required this.title,
    this.icon,
    this.body,
    this.details = const <String>[],
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    final _FeedbackPalette palette = _paletteFor(tone);
    final effectiveDetails = <String>[
      if ((body ?? '').trim().isNotEmpty) body!.trim(),
      ...details.where((d) => d.trim().isNotEmpty).map((d) => d.trim()),
    ];

    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: palette.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.foreground.withValues(alpha: 0.28)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? palette.icon, size: 20, color: palette.foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: ExerciseThemeTokens.feedback.copyWith(
                    color: palette.foreground,
                    fontSize: 16,
                  ),
                ),
                ...effectiveDetails.map(
                  (line) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      line,
                      style: ExerciseThemeTokens.caption.copyWith(
                        color: palette.foreground.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  _FeedbackPalette _paletteFor(ExerciseFeedbackTone value) {
    switch (value) {
      case ExerciseFeedbackTone.success:
        return const _FeedbackPalette(
          background: ExerciseThemeTokens.successBg,
          foreground: ExerciseThemeTokens.success,
          icon: Icons.check_circle_rounded,
        );
      case ExerciseFeedbackTone.error:
        return const _FeedbackPalette(
          background: ExerciseThemeTokens.errorBg,
          foreground: ExerciseThemeTokens.error,
          icon: Icons.cancel_rounded,
        );
      case ExerciseFeedbackTone.info:
        return const _FeedbackPalette(
          background: ExerciseThemeTokens.accentSoft,
          foreground: ExerciseThemeTokens.accent,
          icon: Icons.info_rounded,
        );
      case ExerciseFeedbackTone.neutral:
        return const _FeedbackPalette(
          background: ExerciseThemeTokens.surfaceMuted,
          foreground: ExerciseThemeTokens.textPrimary,
          icon: Icons.info_rounded,
        );
    }
  }
}

class _FeedbackPalette {
  final Color background;
  final Color foreground;
  final IconData icon;

  const _FeedbackPalette({
    required this.background,
    required this.foreground,
    required this.icon,
  });
}
