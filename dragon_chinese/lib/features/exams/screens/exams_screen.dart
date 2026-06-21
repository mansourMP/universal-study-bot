import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/design_system.dart';

/// Exams Screen
/// Contains: exam list, placement test, progress.
class ExamsScreen extends StatelessWidget {
  const ExamsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppScaffold(title: 'Exams', body: ExamsListView());
  }
}

class ExamsListView extends StatelessWidget {
  const ExamsListView({super.key});

  @override
  Widget build(BuildContext context) {
    final exams = [
      (
        'HSK 1 Practice Test',
        'Test your HSK 1 vocabulary and grammar',
        Icons.school,
        AppColors.primary,
        true,
      ),
      (
        'Placement Test',
        'Find your current level',
        Icons.assessment,
        AppColors.jade,
        false,
      ),
      (
        'Tone Master Challenge',
        'Perfect your 4 tones',
        Icons.music_note,
        AppColors.primaryDark,
        false,
      ),
      (
        'Character Recognition',
        '50 characters in 5 minutes',
        Icons.translate,
        AppColors.gold,
        false,
      ),
      (
        'Listening Comprehension',
        'Test your ear for Mandarin',
        Icons.headphones,
        AppColors.warningDark,
        false,
      ),
    ];

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      children: [
        _ExamTile(item: exams.first),
        const SizedBox(height: AppSpacing.sectionGap),
        Text(
          'Available Exams',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: AppColors.textPrimary),
        ),
        const SizedBox(height: AppSpacing.xs),
        ...exams
            .skip(1)
            .map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: _ExamTile(item: item),
              ),
            ),
      ],
    );
  }
}

class _ExamTile extends StatelessWidget {
  const _ExamTile({required this.item});

  final (String, String, IconData, Color, bool) item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = item.$1;
    final description = item.$2;
    final icon = item.$3;
    final color = item.$4;
    final featured = item.$5;
    final onFeatured = theme.colorScheme.onPrimary;

    return AppCard(
      variant: featured ? AppCardVariant.hero : AppCardVariant.standard,
      child: Container(
        decoration: featured
            ? BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadius.heroCard),
              )
            : null,
        padding: featured
            ? const EdgeInsets.all(AppSpacing.sm)
            : EdgeInsets.zero,
        child: AppListRow(
          leading: Container(
            padding: const EdgeInsets.all(AppSpacing.xxs),
            decoration: BoxDecoration(
              color: featured
                  ? onFeatured.withValues(alpha: 0.14)
                  : color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.button),
            ),
            child: Icon(icon, color: featured ? onFeatured : color),
          ),
          title: title,
          subtitle: description,
          trailing: Icon(
            Icons.chevron_right,
            color: featured ? onFeatured : AppColors.textTertiary,
          ),
        ),
      ),
    );
  }
}
