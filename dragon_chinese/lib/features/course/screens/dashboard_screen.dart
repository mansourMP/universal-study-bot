import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:dragon_chinese/design_system/design_system.dart';
import 'package:dragon_chinese/features/course/models/lesson_model.dart';
import 'package:dragon_chinese/features/course/widgets/constellation_skills_grid.dart';
import 'package:dragon_chinese/features/course/screens/reading_screen.dart';
import 'package:dragon_chinese/features/course/screens/vocabulary_levels_screen.dart';
import 'package:dragon_chinese/features/course/screens/image_matching_levels_screen.dart';
import 'package:dragon_chinese/features/course/screens/skill_drill_levels_screen.dart';
import 'package:dragon_chinese/features/course/screens/listening_levels_screen.dart';
import 'package:dragon_chinese/features/exams/screens/exams_screen.dart';
import 'package:dragon_chinese/core/constants/languages.dart';
import 'package:dragon_chinese/design_system/widgets/animated_flag.dart';
import 'package:dragon_chinese/features/course/screens/brain_exercise_runner_screen.dart';
import 'package:dragon_chinese/features/course/screens/exercise_debug_gallery_screen.dart';
import 'package:dragon_chinese/features/course/widgets/map_path_components.dart';
import 'package:dragon_chinese/features/course/adapters/path_view_models.dart';
import 'package:dragon_chinese/features/course/controllers/dashboard_controller.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/features/course/services/goal_profile.dart';
import 'package:dragon_chinese/features/course/services/goal_profile_store.dart';
import 'package:dragon_chinese/features/course/screens/readiness_screen.dart';
import 'package:dragon_chinese/core/net/api_result.dart';
import 'package:dragon_chinese/core/utils/app_log.dart';
import 'package:dragon_chinese/core/widgets/network_state_gate.dart';

class DashboardScreen extends StatefulWidget {
  final String currentSourceLang;
  final String currentTargetLang;
  final Function(String) onLanguageChanged;
  final Function(String) onTargetLanguageChanged;
  final VoidCallback? onMenuTap;
  final DashboardController? controller;
  final bool showMissionCard;

  const DashboardScreen({
    super.key,
    required this.currentSourceLang,
    required this.currentTargetLang,
    required this.onLanguageChanged,
    required this.onTargetLanguageChanged,
    this.onMenuTap,
    this.controller,
    this.showMissionCard = true,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _activePageIndex = 0; // 0 = Path, 1 = Skills, 2 = Explore
  GoalProfile? _goalProfile;
  late final DashboardController _controller;

  // New: Use ApiResult for typed error handling
  ApiResult<DashboardData>? _dashboardResult;
  bool _isLoading = false;
  final Set<String> _optimisticCompletedLessonIds = <String>{};

  late ScrollController _pathScrollController;

  @override
  void initState() {
    super.initState();
    _pathScrollController = ScrollController();
    _controller = widget.controller ?? DashboardController();
    _loadGoalProfile();
    _loadData();
  }

  @override
  void dispose() {
    _pathScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    AppLog.d('Loading dashboard data...');
    setState(() => _isLoading = true);

    final result = await _controller.loadResult();

    if (!mounted) return;
    setState(() {
      _dashboardResult = result;
      _isLoading = false;
    });

    if (result.isSuccess) {
      final data = (result as ApiSuccess<DashboardData>).data;
      AppLog.i('Loaded ${data.lessons.length} lessons');
    } else {
      final failure = result as ApiFailure;
      AppLog.e('Failed to load dashboard', error: failure.message);
    }
  }

  Future<void> _loadGoalProfile() async {
    final profile = await GoalProfileStore.loadProfile();
    if (!mounted) return;
    setState(() => _goalProfile = profile);
  }

  void _onLessonComplete(String lessonId) {
    // Advance path circle immediately after a successful lesson completion.
    setState(() {
      _optimisticCompletedLessonIds.add(lessonId);
    });
    // Then refresh from backend source of truth.
    _loadData();
  }

  void _showLanguagePicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(DragonSpacing.radiusLg),
        ),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.7,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, controller) {
            final languages = AppLanguages.supported;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    DragonSpacing.md,
                    DragonSpacing.md,
                    DragonSpacing.md,
                    DragonSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Choose languages',
                        style: DragonTypography.titleMedium,
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: controller,
                    padding: const EdgeInsets.fromLTRB(
                      DragonSpacing.md,
                      0,
                      DragonSpacing.md,
                      DragonSpacing.md,
                    ),
                    children: [
                      Text(
                        'Target language',
                        style: DragonTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: DragonSpacing.xs),
                      Wrap(
                        spacing: DragonSpacing.xs,
                        runSpacing: DragonSpacing.xs,
                        children: languages.map((lang) {
                          final code = lang['code']!;
                          final isSelected = code == widget.currentTargetLang;
                          return ChoiceChip(
                            selected: isSelected,
                            label: Text('${lang['flag']} ${lang['name']}'),
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              widget.onTargetLanguageChanged(code);
                            },
                            selectedColor: AppColors.primary.withValues(
                              alpha: 0.18,
                            ),
                            checkmarkColor: AppColors.primary,
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: DragonSpacing.lg),
                      Text(
                        'Native language',
                        style: DragonTypography.titleSmall.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: DragonSpacing.xs),
                      Wrap(
                        spacing: DragonSpacing.xs,
                        runSpacing: DragonSpacing.xs,
                        children: languages.map((lang) {
                          final code = lang['code']!;
                          final isSelected = code == widget.currentSourceLang;
                          return ChoiceChip(
                            selected: isSelected,
                            label: Text('${lang['flag']} ${lang['name']}'),
                            onSelected: (_) {
                              HapticFeedback.selectionClick();
                              widget.onLanguageChanged(code);
                            },
                            selectedColor: AppColors.jade.withValues(
                              alpha: 0.18,
                            ),
                            checkmarkColor: AppColors.jadeDark,
                            side: BorderSide(
                              color: isSelected
                                  ? AppColors.jadeDark
                                  : AppColors.border,
                            ),
                            labelStyle: TextStyle(
                              color: isSelected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PathThemeTokens.background,
      // FAB Removed
      body: SafeArea(
        child: DsPage(
          child: Column(
            children: [
              _buildHeader(),
              _buildViewModeToggle(),
              Expanded(
                child: IndexedStack(
                  index: _activePageIndex,
                  children: [
                    _buildPathView(),
                    _buildSkillsView(),
                    _buildExploreView(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        if (widget.onMenuTap != null)
                          IconButton(
                            icon: const Icon(Icons.menu_rounded),
                            color: PathThemeTokens.textPrimary,
                            tooltip: 'Open side panel',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 34,
                              minHeight: 34,
                            ),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              HapticFeedback.selectionClick();
                              widget.onMenuTap?.call();
                            },
                          ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: _showLanguagePicker,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: AppColors.border,
                                width: 2,
                              ),
                            ),
                            child: AnimatedFlag(
                              targetLang: widget.currentTargetLang,
                              nativeLang: widget.currentSourceLang,
                              size: 32,
                              showNativeOverlay: true,
                            ),
                          ),
                        ),
                        if (kDebugMode && !isNarrow) const Spacer(),
                        if (kDebugMode && !isNarrow)
                          IconButton(
                            icon: const Icon(Icons.developer_mode),
                            color: PathThemeTokens.textSecondary,
                            tooltip: 'Exercise debug gallery',
                            onPressed: () {
                              Navigator.of(
                                context,
                              ).pushNamed(ExerciseDebugGalleryScreen.routeName);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildViewModeToggle() {
    return Transform.translate(
      offset: const Offset(0, -4),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
        child: AppSegmentedControl<int>(
          value: _activePageIndex,
          options: const {0: 'Path', 1: 'Skills', 2: 'Explore'},
          onChanged: _switchHubTab,
        ),
      ),
    );
  }

  void _switchHubTab(int index) {
    if (_activePageIndex == index) return;
    HapticFeedback.selectionClick();
    setState(() => _activePageIndex = index);
  }

  Widget _buildPathView() {
    return NetworkStateGate<DashboardData>(
      result: _dashboardResult,
      isLoading: _isLoading,
      onRetry: _loadData,
      isEmpty: (data) => data.lessons.isEmpty,
      emptyMessage: 'No lessons available',
      builder: (data) => _buildPathContent(data),
    );
  }

  Widget _buildPathContent(DashboardData data) {
    final lessonsList = data.lessons;
    final adapter = PathAdapter(goalProfile: _goalProfile);
    final units = adapter.buildUnits(lessonsList, 0);
    final isCompact = DsBreakpoints.of(context) == DsBreakpoint.compact;
    final orbitHorizontalPadding = isCompact ? DsSpacing.xs : DsSpacing.md;

    // Find current unit
    final currentUnit = units.firstWhere(
      (u) => u.lessons.any((l) => l.state != LessonState.completed),
      orElse: () => units.last,
    );
    final unitIndex = units.indexOf(currentUnit) + 1;
    final partIndex = ((unitIndex - 1) ~/ 8) + 1;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.xs),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compactAction = constraints.maxWidth < 430;
              return Row(
                children: [
                  Expanded(
                    child: _PathUnitHeaderChip(
                      partIndex: partIndex,
                      unitIndex: unitIndex,
                      unitTitle: currentUnit.unitTitle,
                      completed: currentUnit.completed,
                      total: currentUnit.total,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: DsSpacing.sm),
                    child: compactAction
                        ? IconButton(
                            tooltip: 'All lessons',
                            onPressed: () => _showAllLessonsSheet(units),
                            icon: const Icon(Icons.list_alt_rounded, size: 20),
                            style: IconButton.styleFrom(
                              backgroundColor: AppColors.surface,
                              side: const BorderSide(color: AppColors.border),
                              visualDensity: VisualDensity.compact,
                            ),
                          )
                        : OutlinedButton.icon(
                            onPressed: () => _showAllLessonsSheet(units),
                            icon: const Icon(Icons.list_alt_rounded, size: 16),
                            label: const Text(
                              'All lessons',
                              overflow: TextOverflow.ellipsis,
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: DsSpacing.sm),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              orbitHorizontalPadding,
              DsSpacing.md,
              orbitHorizontalPadding,
              DsSpacing.lg,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final breakpoint = DsBreakpoints.of(context);
                final pageMaxWidth = DsLayout.pageMaxWidth(context);
                final boundedMaxWidth = pageMaxWidth.isFinite
                    ? pageMaxWidth
                    : constraints.maxWidth;
                final rawAvailableWidth = min(
                  constraints.maxWidth,
                  boundedMaxWidth,
                );
                final rawOrbitDiameter = rawAvailableWidth.clamp(300.0, 720.0);
                final maxByHeight = max(260.0, constraints.maxHeight - 24);
                final orbitDiameter = min(rawOrbitDiameter, maxByHeight);
                final nodeSize = (orbitDiameter * 0.21)
                    .clamp(56.0, 92.0)
                    .toDouble();
                final centerSize = (orbitDiameter * 0.24)
                    .clamp(62.0, 108.0)
                    .toDouble();
                final ringRadius = (orbitDiameter * 0.38)
                    .clamp(108.0, 280.0)
                    .toDouble();
                final indicatorTopOffset = -((nodeSize * 0.58)
                    .clamp(26.0, 44.0)
                    .toDouble());
                final orbitCanvasHeight = orbitDiameter + nodeSize * 0.72;
                final lessonOrbitNodes = _buildLessonOrbitNodes(
                  currentUnit.lessons,
                );
                final orbitNodes = <_OrbitNode>[...lessonOrbitNodes];
                final nodeCount = orbitNodes.length;
                final traceStartIndex = 0;
                final traceNodeCount = lessonOrbitNodes.length;
                final currentLessonLocalIndex = lessonOrbitNodes.indexWhere(
                  (node) => node.isCurrent,
                );
                final completedLessonCount = lessonOrbitNodes
                    .where((node) => node.isCompleted)
                    .length;
                final highlightedLessonLocalIndex = currentLessonLocalIndex >= 0
                    ? currentLessonLocalIndex
                    : (completedLessonCount > 0
                          ? completedLessonCount - 1
                          : -1);

                final orbitCanvas = SizedBox(
                  width: orbitDiameter,
                  height: orbitCanvasHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: Size(orbitDiameter, orbitCanvasHeight),
                        painter: OrbitTracePainter(
                          nodeCount: nodeCount,
                          ringRadius: ringRadius,
                          traceStartIndex: traceStartIndex,
                          traceNodeCount: traceNodeCount,
                          highlightedLessonLocalIndex:
                              highlightedLessonLocalIndex,
                        ),
                      ),
                      _CenterReadinessHub(
                        size: centerSize,
                        onTap: _openReadiness,
                      ),
                      ...List.generate(nodeCount, (idx) {
                        final orbitNode = orbitNodes[idx];

                        final angleStep = nodeCount <= 1
                            ? 360.0
                            : 360.0 / nodeCount;
                        final double angle =
                            (idx * angleStep - 90.0) * (pi / 180.0);
                        final double x = cos(angle) * ringRadius;
                        final double y = sin(angle) * ringRadius;

                        final isLocked = orbitNode.isLocked;
                        final isCompleted = orbitNode.isCompleted;
                        final isCurrent = orbitNode.isCurrent;

                        return TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0.0, end: 1.0),
                          duration: Duration(milliseconds: 400 + (idx * 100)),
                          curve: Curves.easeOutBack,
                          builder: (context, value, child) {
                            return Transform.translate(
                              offset: Offset(x, y),
                              child: Opacity(
                                opacity: value.clamp(0.0, 1.0),
                                child: Transform.scale(
                                  scale: value,
                                  child: Stack(
                                    clipBehavior: Clip.none,
                                    alignment: Alignment.center,
                                    children: [
                                      if (isCurrent)
                                        Positioned(
                                          top: indicatorTopOffset,
                                          child: const _StartIndicator(),
                                        ),
                                      PathNode(
                                        index: idx,
                                        isLocked: isLocked,
                                        isCompleted: isCompleted,
                                        isCurrent: isCurrent,
                                        icon: orbitNode.icon,
                                        type: orbitNode.type,
                                        size: nodeSize,
                                        ringSlots: orbitNode.ringSlots,
                                        ringProgress: orbitNode.ringProgress,
                                        onTap: orbitNode.onTap,
                                      ),
                                      if (orbitNode.badge != null)
                                        Positioned(
                                          bottom: -((nodeSize * 0.34).clamp(
                                            18.0,
                                            30.0,
                                          )),
                                          child: _OrbitNodeBadge(
                                            label: orbitNode.badge!,
                                            compact:
                                                breakpoint ==
                                                DsBreakpoint.compact,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      }),
                    ],
                  ),
                );

                return Center(child: orbitCanvas);
              },
            ),
          ),
        ),
      ],
    );
  }

  void _onLessonTap(LessonVM lesson) {
    final status = lesson.lesson.status;
    if (status == 'locked' || lesson.state == LessonState.locked) {
      HapticFeedback.selectionClick();
      _showLockedLessonPreview(context, lesson);
      return;
    }
    HapticFeedback.mediumImpact();
    _showMissionCard(context, lesson.lesson);
  }

  void _showLockedLessonPreview(BuildContext context, LessonVM lesson) {
    final unitTitle = lesson.lesson.metadata?['unit_title']?.toString().trim();
    final kind = lesson.lesson.metadata?['type']?.toString().trim();
    final unlockReason = lesson.lesson.unlockReason?.trim();
    final objective = lesson.promise.trim();

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                lesson.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                [
                  if (unitTitle != null && unitTitle.isNotEmpty) unitTitle,
                  if (kind != null && kind.isNotEmpty) kind.toUpperCase(),
                ].join(' • '),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                objective.isNotEmpty
                    ? objective
                    : 'This lesson trains the next required skill before unlock.',
                style: const TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Unlock rule: ${unlockReason?.isNotEmpty == true ? unlockReason : 'Complete previous lesson(s).'}',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE5E7EB),
                    foregroundColor: const Color(0xFF6B7280),
                    disabledBackgroundColor: const Color(0xFFE5E7EB),
                    disabledForegroundColor: const Color(0xFF6B7280),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('LOCKED'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<_OrbitNode> _buildLessonOrbitNodes(List<LessonVM> lessons) {
    if (lessons.isEmpty) return const <_OrbitNode>[];

    String? forcedCurrentId;
    for (final lesson in lessons) {
      final id = lesson.lesson.lessonId;
      final done =
          lesson.state == LessonState.completed ||
          _optimisticCompletedLessonIds.contains(id);
      final backendLocked = lesson.state == LessonState.locked;
      if (!done && !backendLocked) {
        forcedCurrentId = id;
        break;
      }
    }
    forcedCurrentId ??= lessons
        .map((l) => l.lesson.lessonId)
        .firstWhere(
          (id) => !_optimisticCompletedLessonIds.contains(id),
          orElse: () => lessons.first.lesson.lessonId,
        );

    return lessons
        .map(
          (lesson) => _OrbitNode.lesson(
            lesson: lesson,
            type: _lessonOrbitType(lesson),
            onTap: () => _onLessonTap(lesson),
            optimisticCompleted: _optimisticCompletedLessonIds.contains(
              lesson.lesson.lessonId,
            ),
            forcedCurrentId: forcedCurrentId!,
          ),
        )
        .toList(growable: false);
  }

  void _openReadiness() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ReadinessScreen()));
  }

  Widget _buildSkillsView() {
    return NetworkStateGate<DashboardData>(
      result: _dashboardResult,
      isLoading: _isLoading,
      onRetry: _loadData,
      emptyMessage: 'No skills data available',
      builder: (data) => _buildSkillsContent(data),
    );
  }

  Widget _buildExploreView() {
    return const ExamsListView();
  }

  Widget _buildSkillsContent(DashboardData data) {
    final mastery = data.masteryStats;
    final skills = [
      (
        'Vocabulary',
        Icons.grid_view_rounded,
        const Color(0xFF58CC02),
        'Learn',
        mastery['vocabulary'] ?? 0.0,
      ),
      (
        'Matching',
        Icons.extension_rounded,
        const Color(0xFFFF9800),
        'Play',
        0.0,
      ),
      (
        'Reading',
        Icons.menu_book_rounded,
        const Color(0xFF1CB0F6),
        'Review',
        mastery['reading'] ?? 0.0,
      ),
      (
        'Listening',
        Icons.headphones_rounded,
        const Color(0xFFFF4B4B),
        'Audio',
        0.0,
      ),
      ('Speaking', Icons.mic_rounded, const Color(0xFFCE82FF), 'Speech', 0.0),
      ('Writing', Icons.edit_rounded, const Color(0xFFFFC800), 'Chars', 0.0),
    ];

    final constellationSkills = skills
        .asMap()
        .entries
        .map(
          (entry) => ConstellationSkill(
            title: entry.value.$1,
            subtitle: entry.value.$4,
            icon: entry.value.$2,
            color: entry.value.$3,
            progress: entry.value.$5,
            onTap: () => _launchSkillPractice(entry.value.$1),
          ),
        )
        .toList();

    return ConstellationSkillsGrid(skills: constellationSkills);
  }

  Future<void> _launchSkillPractice(String skillName) async {
    if (skillName == 'Vocabulary') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VocabularyLevelsScreen(
            sourceLang: widget.currentSourceLang,
            targetLang: widget.currentTargetLang,
          ),
        ),
      );
      return;
    }

    if (skillName == 'Matching') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ImageMatchingLevelsScreen(
            sourceLang: widget.currentSourceLang,
            targetLang: widget.currentTargetLang,
          ),
        ),
      );
      return;
    }

    if (skillName == 'Reading') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              ReadingScreen(sourceLang: widget.currentSourceLang),
        ),
      );
      return;
    }

    if (skillName == 'Listening') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ListeningLevelsScreen(
            sourceLang: widget.currentSourceLang,
            targetLang: widget.currentTargetLang,
          ),
        ),
      );
      return;
    }

    if (skillName == 'Speaking') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SkillDrillLevelsScreen(
            sourceLang: widget.currentSourceLang,
            targetLang: widget.currentTargetLang,
            skillTitle: 'Speaking',
            focusDimension: 'production',
            setIcon: Icons.mic_rounded,
            accentColor: AppColors.secondary,
            contentEnabled: false,
            pendingMessage: 'Speaking hub is coming soon.',
          ),
        ),
      );
      return;
    }

    if (skillName == 'Writing') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => SkillDrillLevelsScreen(
            sourceLang: widget.currentSourceLang,
            targetLang: widget.currentTargetLang,
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
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$skillName exercises will be available soon')),
    );
  }

  void _showMissionCard(BuildContext context, Lesson lesson) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface.withValues(alpha: 0),
      builder: (context) => _MissionCard(
        userId: AppConfig.userId,
        lesson: lesson,
        onComplete: _onLessonComplete,
      ),
    );
  }

  void _showAllLessonsSheet(List<UnitVM> units) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.82,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'All Lessons',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
                    itemCount: units.length,
                    itemBuilder: (context, unitIdx) {
                      final unit = units[unitIdx];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${unitIdx + 1}. ${unit.unitTitle}',
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${unit.completed}/${unit.total} completed',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ...unit.lessons.map((lesson) {
                                final locked =
                                    lesson.state == LessonState.locked;
                                final completed =
                                    lesson.state == LessonState.completed;
                                final current =
                                    lesson.state == LessonState.current;
                                final statusText = completed
                                    ? 'Completed'
                                    : (current ? 'Current' : 'Locked');
                                return ListTile(
                                  dense: true,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                  ),
                                  leading: Icon(
                                    completed
                                        ? Icons.check_circle_rounded
                                        : (locked
                                              ? Icons.lock_rounded
                                              : Icons.play_circle_fill_rounded),
                                    color: completed
                                        ? const Color(0xFF22A06B)
                                        : (locked
                                              ? AppColors.textSecondary
                                              : AppColors.primary),
                                  ),
                                  title: Text(
                                    lesson.title,
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  subtitle: Text(
                                    statusText,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onTap: () {
                                    Navigator.pop(context);
                                    _onLessonTap(lesson);
                                  },
                                );
                              }),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _lessonOrbitType(LessonVM lesson) {
    final rawType =
        (lesson.lesson.metadata?['type'] as String?) ?? lesson.lesson.mode;
    final normalized = rawType.toLowerCase();
    if (normalized.contains('speak')) return 'speaking';
    if (normalized.contains('listen') || normalized.contains('audio')) {
      return 'listening';
    }
    if (normalized.contains('story') || normalized.contains('read')) {
      return 'story';
    }
    if (normalized.contains('check') || normalized.contains('quiz')) {
      return 'checkpoint';
    }
    if (normalized.contains('practice') || normalized.contains('drill')) {
      return 'practice';
    }
    return 'learn';
  }
}

class _PathUnitHeaderChip extends StatelessWidget {
  const _PathUnitHeaderChip({
    required this.partIndex,
    required this.unitIndex,
    required this.unitTitle,
    required this.completed,
    required this.total,
  });

  final int partIndex;
  final int unitIndex;
  final String unitTitle;
  final int completed;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Material(
        color: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: DsSpacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.border.withValues(alpha: 0.45)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.xxs),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: AppColors.primary,
                  size: 16,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Part $partIndex • Unit $unitIndex • $completed/$total lessons',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    unitTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StartIndicator extends StatefulWidget {
  const _StartIndicator();
  @override
  State<_StartIndicator> createState() => _StartIndicatorState();
}

class _StartIndicatorState extends State<_StartIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _pulseAnimation.value,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: DsSpacing.md,
                  vertical: DsSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FBFF),
                  borderRadius: BorderRadius.circular(DsRadii.pill),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF000000).withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Text(
                  "START",
                  style: DsTypography.label.copyWith(
                    color: const Color(0xFF2B5BB3),
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              Transform.rotate(
                angle: pi / 4,
                child: Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FBFF),
                    border: Border(
                      right: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                      bottom: BorderSide(color: Color(0xFFE2E8F0), width: 1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CenterReadinessHub extends StatelessWidget {
  const _CenterReadinessHub({required this.size, required this.onTap});

  final double size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 1.65,
      height: size * 1.65,
      child: GestureDetector(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        behavior: HitTestBehavior.opaque,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              bottom: size * 0.20,
              child: Container(
                width: size * 1.2,
                height: size * 0.22,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(DsRadii.pill),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF000000).withValues(alpha: 0.10),
                      blurRadius: 12,
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: size * 1.34,
              height: size * 1.34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFFFFFFF).withValues(alpha: 0.92),
                    const Color(0xFFF3F7FF),
                  ],
                ),
                border: Border.all(color: const Color(0xFFDCE6F5)),
              ),
            ),
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF6E91D4), Color(0xFF5C80C7)],
                ),
                border: Border.all(color: const Color(0xFFE7EEFB)),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF000000).withValues(alpha: 0.14),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.auto_stories_rounded,
              size: size * 0.58,
              color: const Color(0xFFDCE8FF),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrbitNode {
  final String id;
  final IconData icon;
  final String type;
  final bool isLocked;
  final bool isCompleted;
  final bool isCurrent;
  final int ringSlots;
  final double ringProgress;
  final VoidCallback onTap;
  final String? badge;

  const _OrbitNode({
    required this.id,
    required this.icon,
    required this.type,
    required this.isLocked,
    required this.isCompleted,
    required this.isCurrent,
    this.ringSlots = 7,
    this.ringProgress = 0,
    required this.onTap,
    this.badge,
  });

  factory _OrbitNode.lesson({
    required LessonVM lesson,
    required String type,
    required VoidCallback onTap,
    required bool optimisticCompleted,
    required String forcedCurrentId,
  }) {
    final id = lesson.lesson.lessonId;
    final isCompleted =
        lesson.state == LessonState.completed || optimisticCompleted;
    final isCurrent = !isCompleted && id == forcedCurrentId;
    final isLocked =
        !isCompleted && !isCurrent && lesson.state == LessonState.locked;
    final ringSlotsRaw = lesson.lesson.metadata?['ring_slots'];
    int ringSlots = 7;
    if (ringSlotsRaw is int) {
      ringSlots = ringSlotsRaw;
    } else if (ringSlotsRaw is String) {
      ringSlots = int.tryParse(ringSlotsRaw) ?? 7;
    }

    return _OrbitNode(
      id: id,
      icon: lesson.icon,
      type: type,
      isLocked: isLocked,
      isCompleted: isCompleted,
      isCurrent: isCurrent,
      ringSlots: ringSlots.clamp(3, 8).toInt(),
      ringProgress: isCompleted ? 1.0 : lesson.progress.clamp(0.0, 1.0),
      onTap: onTap,
      badge: _lessonBadge(lesson.title),
    );
  }
}

String? _lessonBadge(String title) {
  final clean = title.trim();
  if (clean.isEmpty) return null;
  final firstWord = clean.split(RegExp(r'\s+')).first;
  if (firstWord.isEmpty) return null;
  if (firstWord.length <= 10) return firstWord;
  return '${firstWord.substring(0, 10)}…';
}

class OrbitTracePainter extends CustomPainter {
  final int nodeCount;
  final double ringRadius;
  final int traceStartIndex;
  final int traceNodeCount;
  final int highlightedLessonLocalIndex;

  OrbitTracePainter({
    required this.nodeCount,
    required this.ringRadius,
    required this.traceStartIndex,
    required this.traceNodeCount,
    required this.highlightedLessonLocalIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (nodeCount == 0) return;

    final center = Offset(size.width / 2, size.height / 2);

    // 1. Draw Ring (Dashed)
    final ringPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Draw dashed circle
    final path = Path()
      ..addOval(Rect.fromCircle(center: center, radius: ringRadius));
    // Simple dash effect
    const dashWidth = 6.0;
    const dashSpace = 6.0;
    double distance = 0.0;
    for (final PathMetric metric in path.computeMetrics()) {
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dashWidth),
          ringPaint,
        );
        distance += dashWidth + dashSpace;
      }
    }

    if (traceNodeCount <= 0) return;

    // 2. Draw Connection from Center to First LESSON node
    final angleStep = nodeCount <= 1 ? 360.0 : 360.0 / nodeCount;
    final firstTraceIndex = traceStartIndex.clamp(0, nodeCount - 1);
    final angle0 = (firstTraceIndex * angleStep - 90.0) * (pi / 180.0);
    final p0 = Offset(
      center.dx + cos(angle0) * ringRadius,
      center.dy + sin(angle0) * ringRadius,
    );

    // Draw line from center (approx top of book) to Node 0
    final startP = center.translate(0, -40); // Approx top of book
    final tracePaint = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    // If first lesson is reached, color it.
    if (highlightedLessonLocalIndex >= 0) {
      tracePaint.color = const Color(0xFFFFC800); // Gold
    }

    canvas.drawLine(startP, p0, tracePaint);

    // 3. Draw Arcs between LESSON nodes only
    final clampedHighlight = highlightedLessonLocalIndex.clamp(
      -1,
      traceNodeCount - 1,
    );
    for (int i = 0; i < traceNodeCount - 1; i++) {
      final globalA = traceStartIndex + i;
      final globalB = traceStartIndex + i + 1;
      if (globalB >= nodeCount) break;

      final angleA = (globalA * angleStep - 90.0) * (pi / 180.0);
      final angleB = (globalB * angleStep - 90.0) * (pi / 180.0);
      final isDone = (i + 1) <= clampedHighlight;

      final segPaint = Paint()
        ..color = isDone ? const Color(0xFFFFC800) : const Color(0xFFE2E8F0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = isDone ? 4.0 : 2.0
        ..strokeCap = StrokeCap.round;

      // Draw arc following the ring curvature
      final rect = Rect.fromCircle(center: center, radius: ringRadius);
      canvas.drawArc(rect, angleA, angleB - angleA, false, segPaint);
    }
  }

  @override
  bool shouldRepaint(covariant OrbitTracePainter oldDelegate) {
    return oldDelegate.nodeCount != nodeCount ||
        oldDelegate.ringRadius != ringRadius ||
        oldDelegate.traceStartIndex != traceStartIndex ||
        oldDelegate.traceNodeCount != traceNodeCount ||
        oldDelegate.highlightedLessonLocalIndex != highlightedLessonLocalIndex;
  }
}

class _OrbitNodeBadge extends StatelessWidget {
  final String label;
  final bool compact;

  const _OrbitNodeBadge({required this.label, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? DsSpacing.xs : DsSpacing.sm,
        vertical: DsSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(DsRadii.pill),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Text(
        label,
        style: DsTypography.label.copyWith(
          color: const Color(0xFF2B5BB3),
          fontWeight: FontWeight.w800,
          fontSize: compact ? 10 : 11,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _MissionCard extends StatefulWidget {
  final String userId;
  final Lesson lesson;
  final ValueChanged<String> onComplete;
  const _MissionCard({
    required this.userId,
    required this.lesson,
    required this.onComplete,
  });

  @override
  State<_MissionCard> createState() => _MissionCardState();
}

class _MissionCardState extends State<_MissionCard> {
  bool _isStarting = false;

  @override
  Widget build(BuildContext context) {
    final title =
        widget.lesson.metadata?['unit_title'] ??
        widget.lesson.cultural?.setting ??
        'LESSON';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(AppRadius.xs),
            ),
          ),
          const SizedBox(height: 32),
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            "${widget.lesson.title} - ${widget.lesson.metadata?['type'] ?? 'Learn'}",
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 40),
          GameButton(
            text: _isStarting ? 'PREPARING...' : 'START LESSON',
            isLoading: _isStarting,
            onPressed: _isStarting
                ? null
                : () async {
                    HapticFeedback.mediumImpact();
                    setState(() => _isStarting = true);

                    // Extract word IDs for forcing (Brain V2)
                    final wordIds =
                        (widget.lesson.metadata?['word_ids'] as List?)
                            ?.map((e) => e.toString())
                            .toList();
                    final allowedWordIds =
                        (widget.lesson.metadata?['allowed_word_ids'] as List?)
                            ?.map((e) => e.toString())
                            .toList();
                    final unitId =
                        widget.lesson.metadata?['unit_id']?.toString() ??
                        widget.lesson.vocabUnitId;
                    final lessonId = widget.lesson.lessonId;

                    Navigator.pop(context); // Close bottom sheet

                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => BrainExerciseRunnerScreen(
                          intent: 'learn',
                          // Keep primary path circles short: 3-5 minutes.
                          targetMinSeconds: 180,
                          targetMaxSeconds: 300,
                          forcedIds: wordIds,
                          allowedWordIds: allowedWordIds,
                          nodeId: lessonId,
                          unitId: unitId,
                          onComplete: () => widget.onComplete(lessonId),
                        ),
                      ),
                    );

                    if (mounted) {
                      setState(() => _isStarting = false);
                    }
                  },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
