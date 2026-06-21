import 'package:flutter/material.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/design_system/design_system.dart';
import 'package:dragon_chinese/design_system/widgets/animated_flag.dart';
import 'package:dragon_chinese/features/course/screens/image_matching_levels_screen.dart';
import 'package:dragon_chinese/features/course/screens/reading_screen.dart';
import 'package:dragon_chinese/features/course/screens/skill_drill_levels_screen.dart';
import 'package:dragon_chinese/features/course/screens/vocabulary_levels_screen.dart';
import 'package:dragon_chinese/features/course/services/adaptive_hint_generator.dart';
import 'package:dragon_chinese/features/course/services/mastery_store.dart';
import 'package:dragon_chinese/features/course/services/skill_service.dart';
import 'package:dragon_chinese/features/course/services/weakness_detector.dart';

class SkillsScreen extends StatefulWidget {
  final String sourceLang;
  final String targetLang;
  const SkillsScreen({
    super.key,
    required this.sourceLang,
    this.targetLang = AppConfig.targetLang,
  });

  @override
  State<SkillsScreen> createState() => _SkillsScreenState();
}

class _SkillsScreenState extends State<SkillsScreen> {
  final SkillService _skillService = SkillService();
  List<SkillGroup> _skillStats = [];
  Map<String, double> _masteryScores = {};
  WeaknessReport? _weaknessReport;
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final skills = await _skillService.fetchSkillStats(
        widget.targetLang,
        sourceLang: widget.sourceLang,
      );
      final mastery = await _skillService.fetchMasteryStats();

      final detector = WeaknessDetector();
      final report = detector.analyze(
        mastery: MasteryStore({}),
        wordIds: [],
        skillScores: mastery,
      );

      if (!mounted) return;
      setState(() {
        _skillStats = skills;
        _masteryScores = mastery;
        _weaknessReport = report;
        _errorMessage = null;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _skillStats = [];
        _masteryScores = {};
        _weaknessReport = null;
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  String _calculateTotalWords() {
    if (_skillStats.isEmpty) return '0';
    int total = 0;
    for (final group in _skillStats) {
      total += group.count;
    }
    return '$total';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: AppProgressIndicator()));
    }

    if (_errorMessage != null) {
      return AppScaffold(
        title: 'Skills',
        subtitle: 'Targeted practice',
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: AppSpacing.xs),
            child: AnimatedFlag(
              targetLang: widget.targetLang,
              nativeLang: widget.sourceLang,
              size: AppSpacing.md + AppSpacing.xxs,
              showNativeOverlay: true,
            ),
          ),
        ],
        body: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppCard(
              variant: AppCardVariant.flat,
              child: AppListRow(
                leading: const Icon(
                  Icons.error_outline_rounded,
                  color: AppColors.error,
                ),
                title: 'Unable to load skills',
                subtitle: _errorMessage,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Retry',
              onPressed: _loadData,
              variant: AppButtonVariant.primary,
            ),
          ],
        ),
      );
    }

    final skills = [
      (
        'Vocabulary',
        Icons.book,
        AppColors.primary,
        '${_calculateTotalWords()} words • ${_skillStats.length} levels',
        null,
      ),
      (
        'Reading',
        Icons.menu_book,
        AppColors.jade,
        'Stories & Texts',
        _masteryScores['reading'] ?? 0.0,
      ),
      (
        'Writing',
        Icons.edit,
        AppColors.gold,
        'Characters & Essays',
        _masteryScores['writing'] ?? 0.0,
      ),
      (
        'Listening',
        Icons.headphones,
        AppColors.primaryDark,
        'Audio & Dialogue',
        _masteryScores['listening'] ?? 0.0,
      ),
      (
        'Speaking',
        Icons.mic,
        AppColors.secondary,
        'Pronunciation',
        _masteryScores['speaking'] ?? 0.0,
      ),
      (
        'Image Matching',
        Icons.image,
        AppColors.jadeDark,
        'Visual Recognition',
        null,
      ),
    ];

    return AppScaffold(
      title: 'Skills',
      subtitle: 'Targeted practice',
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.xs),
          child: AnimatedFlag(
            targetLang: widget.targetLang,
            nativeLang: widget.sourceLang,
            size: AppSpacing.md + AppSpacing.xxs,
            showNativeOverlay: true,
          ),
        ),
      ],
      body: Column(
        children: [
          if (_weaknessReport != null && _weaknessReport!.hasWeaknesses)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: AppCard(
                variant: AppCardVariant.flat,
                child: AppListRow(
                  leading: const Icon(
                    Icons.lightbulb_outline,
                    color: AppColors.primary,
                  ),
                  title: 'Adaptive tip',
                  subtitle: AdaptiveHintGenerator.generateHint(
                    _weaknessReport!,
                  ),
                ),
              ),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final crossAxisCount = width >= 1100
                    ? 4
                    : (width >= 760 ? 3 : 2);
                return GridView.builder(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: AppSpacing.sm,
                    mainAxisSpacing: AppSpacing.sm,
                    childAspectRatio: width >= 760 ? 1.18 : 1.1,
                  ),
                  itemCount: skills.length,
                  itemBuilder: (context, index) {
                    final skill = skills[index];
                    final progress = skill.$5 ?? 0.0;
                    return AppCard(
                      variant: AppCardVariant.hero,
                      onTap: () {
                        switch (index) {
                          case 0:
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => VocabularyLevelsScreen(
                                  sourceLang: widget.sourceLang,
                                  targetLang: widget.targetLang,
                                ),
                              ),
                            );
                            return;
                          case 1:
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ReadingScreen(
                                  sourceLang: widget.sourceLang,
                                ),
                              ),
                            );
                            return;
                          case 2:
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SkillDrillLevelsScreen(
                                  sourceLang: widget.sourceLang,
                                  targetLang: widget.targetLang,
                                  skillTitle: 'Writing',
                                  focusDimension: 'production',
                                  setIcon: Icons.edit_rounded,
                                  accentColor: AppColors.gold,
                                  contentEnabled: false,
                                  pendingMessage: 'Writing hub is coming soon.',
                                ),
                              ),
                            );
                            return;
                          case 3:
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SkillDrillLevelsScreen(
                                  sourceLang: widget.sourceLang,
                                  targetLang: widget.targetLang,
                                  skillTitle: 'Listening',
                                  focusDimension: 'listening',
                                  setIcon: Icons.headphones_rounded,
                                  accentColor: AppColors.primaryDark,
                                  contentEnabled: false,
                                  pendingMessage:
                                      'Listening hub is coming soon.',
                                ),
                              ),
                            );
                            return;
                          case 4:
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SkillDrillLevelsScreen(
                                  sourceLang: widget.sourceLang,
                                  targetLang: widget.targetLang,
                                  skillTitle: 'Speaking',
                                  focusDimension: 'production',
                                  setIcon: Icons.mic_rounded,
                                  accentColor: AppColors.secondary,
                                  contentEnabled: false,
                                  pendingMessage:
                                      'Speaking hub is coming soon.',
                                ),
                              ),
                            );
                            return;
                          case 5:
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ImageMatchingLevelsScreen(
                                  sourceLang: widget.sourceLang,
                                  targetLang: widget.targetLang,
                                ),
                              ),
                            );
                            return;
                        }
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(AppSpacing.xxs),
                                decoration: BoxDecoration(
                                  color: skill.$3.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(skill.$2, color: skill.$3),
                              ),
                              const Spacer(),
                              Text(
                                '${(progress * 100).round()}%',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: skill.$3,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            skill.$1,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: AppSpacing.xxxs),
                          Text(
                            skill.$4,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                          const Spacer(),
                          AppProgressBar(value: progress),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
