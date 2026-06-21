import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/design_system.dart';
import 'package:dragon_chinese/features/course/models/study_session.dart';

/// Quick Study Introduction Screen
/// Shows all words in the session as swipeable cards
class QuickStudyIntroScreen extends StatefulWidget {
  final StudySession session;

  const QuickStudyIntroScreen({super.key, required this.session});

  @override
  State<QuickStudyIntroScreen> createState() => _QuickStudyIntroScreenState();
}

class _QuickStudyIntroScreenState extends State<QuickStudyIntroScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = widget.session.wordCount == 0
        ? 0.0
        : (_currentPage + 1) / widget.session.wordCount;

    return AppScaffold(
      title: widget.session.unitTitle,
      subtitle: '${_currentPage + 1}/${widget.session.wordCount}',
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Text(
                  'Word ${_currentPage + 1} of ${widget.session.wordCount}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${widget.session.wordCount} words to learn',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          AppProgressBar(value: progress),
          const SizedBox(height: AppSpacing.sm),

          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.session.words.length,
              onPageChanged: (index) {
                setState(() {
                  _currentPage = index;
                });
              },
              itemBuilder: (context, index) {
                final word = widget.session.words[index];
                return _buildWordCard(word);
              },
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                if (_currentPage > 0)
                  Expanded(
                    child: AppButton(
                      label: 'Previous',
                      variant: AppButtonVariant.secondary,
                      onPressed: () {
                        _pageController.previousPage(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeInOut,
                        );
                      },
                    ),
                  ),
                if (_currentPage > 0) const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: AppButton(
                    label: _currentPage < widget.session.words.length - 1
                        ? 'Next'
                        : 'Start Practice',
                    variant: AppButtonVariant.primary,
                    fullWidth: true,
                    onPressed: () {
                      if (_currentPage < widget.session.words.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeInOut,
                        );
                      } else {
                        Navigator.pushReplacementNamed(
                          context,
                          '/quick-study-exercise',
                          arguments: widget.session,
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordCard(SessionWord word) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: AppCard(
        variant: AppCardVariant.hero,
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              word.headword,
              style: DragonTypography.hanziLarge.copyWith(
                fontSize: DragonTypography.hanziLarge.fontSize! + AppSpacing.lg,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              word.pronunciation,
              style: DragonTypography.pinyinLarge.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Divider(color: theme.colorScheme.outline.withValues(alpha: 0.25)),
            const SizedBox(height: AppSpacing.md),
            Text(
              word.translation,
              style: DragonTypography.headlineLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (word.exampleSentence.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              AppCard(
                variant: AppCardVariant.flat,
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Text(
                  word.exampleSentence,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
