import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/core/constants/persona_avatars.dart';
import 'package:dragon_chinese/design_system/design_system.dart';
import 'package:dragon_chinese/features/course/screens/brain_exercise_runner_screen.dart';
import 'package:dragon_chinese/features/course/services/listening_service.dart';
import 'package:dragon_chinese/features/course/widgets/hub_card_entrance.dart';

class ListeningLevelsScreen extends StatefulWidget {
  final String sourceLang;
  final String targetLang;

  const ListeningLevelsScreen({
    super.key,
    this.sourceLang = 'en',
    this.targetLang = AppConfig.targetLang,
  });

  @override
  State<ListeningLevelsScreen> createState() => _ListeningLevelsScreenState();
}

class _ListeningLevelsScreenState extends State<ListeningLevelsScreen> {
  final ListeningService _service = ListeningService();

  int? _selectedLevel;
  List<ListeningLevelGroup> _levels = [];
  final Map<int, List<ListeningLesson>> _lessonsByLevel = {};
  bool _isLoading = true;
  bool _isLoadingLessons = false;
  String? _errorMessage;
  String? _lessonError;

  @override
  void initState() {
    super.initState();
    _loadLevels();
  }

  Future<void> _loadLevels() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _lessonError = null;
    });
    try {
      final groups = await _service.fetchLevels(
        widget.targetLang,
        sourceLang: widget.sourceLang,
      );
      if (!mounted) return;
      final selected = _resolveSelectedLevel(
        selectedLevel: _selectedLevel,
        levels: groups,
      );
      setState(() {
        _levels = groups;
        _selectedLevel = selected;
        _isLoading = false;
      });
      if (selected != null) {
        await _loadLessonsForLevel(selected, force: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _levels = [];
        _selectedLevel = null;
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadLessonsForLevel(int level, {bool force = false}) async {
    if (!force && _lessonsByLevel.containsKey(level)) return;
    setState(() {
      _isLoadingLessons = true;
      _lessonError = null;
    });
    try {
      final lessons = await _service.fetchLessonsForLevel(
        level: level,
        sourceLang: widget.sourceLang,
        targetLang: widget.targetLang,
      );
      if (!mounted) return;
      setState(() {
        _lessonsByLevel[level] = lessons;
        _isLoadingLessons = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingLessons = false;
        _lessonError = e.toString();
      });
    }
  }

  int? _resolveSelectedLevel({
    required int? selectedLevel,
    required List<ListeningLevelGroup> levels,
  }) {
    if (levels.isEmpty) return null;
    if (selectedLevel == null) return levels.first.level;
    final exists = levels.any((l) => l.level == selectedLevel);
    return exists ? selectedLevel : levels.first.level;
  }

  List<ListeningLesson> get _selectedLessons {
    final level = _selectedLevel;
    if (level == null) return const [];
    return _lessonsByLevel[level] ?? const [];
  }

  Future<void> _onSelectLevel(int level) async {
    if (_selectedLevel == level) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedLevel = level);
    await _loadLessonsForLevel(level);
  }

  Future<void> _openLesson(ListeningLesson lesson) async {
    HapticFeedback.mediumImpact();
    try {
      final detail = await _service.fetchLessonDetail(
        lesson.id,
        sourceLang: widget.sourceLang,
        targetLang: widget.targetLang,
      );
      if (!mounted) return;
      final resolved = detail.lesson;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => BrainExerciseRunnerScreen(
            intent: resolved.intent,
            focusDimension: resolved.focusDimension,
            exerciseCount: resolved.questionCount,
            forcedIds: resolved.forcedIds,
            nodeId: resolved.id,
            unitId: 'LISTENING_L${resolved.level}',
            targetMinSeconds: resolved.targetMinSeconds,
            targetMaxSeconds: resolved.targetMaxSeconds,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open lesson: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Listening Hub',
      subtitle: 'Real lessons • audio + comprehension',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_errorMessage != null)
            AppCard(
              variant: AppCardVariant.flat,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppListRow(
                    leading: const Icon(
                      Icons.error_outline_rounded,
                      color: AppColors.error,
                    ),
                    title: 'Failed to load listening levels',
                    subtitle: _errorMessage,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppButton(
                    label: 'Retry',
                    onPressed: _loadLevels,
                    variant: AppButtonVariant.primary,
                  ),
                ],
              ),
            ),
          if (_levels.isNotEmpty) ...[
            _buildLevelSelector(),
            const Divider(height: 1),
          ],
          Expanded(
            child: _isLoading
                ? const Center(child: AppProgressIndicator())
                : _buildLessonGrid(),
          ),
        ],
      ),
    );
  }

  Widget _buildLevelSelector() {
    final selectedLevel = _selectedLevel;
    return Container(
      height: 90,
      padding: const EdgeInsets.symmetric(vertical: 12),
      color: Colors.white,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _levels.length,
        itemBuilder: (context, index) {
          final group = _levels[index];
          final level = group.level;
          final isActive = selectedLevel == level;
          final levelDisplay = AppConfig.levelDisplayFromLabel(
            group.label,
            level,
          );

          return GestureDetector(
            onTap: () => _onSelectLevel(level),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 75,
              margin: const EdgeInsets.only(right: 12),
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive ? AppColors.primary : Colors.grey[300]!,
                  width: isActive ? 2 : 1,
                ),
                boxShadow: isActive
                    ? [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : [],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    AppConfig.levelPrefix.toUpperCase(),
                    style: TextStyle(
                      color: isActive
                          ? Colors.white.withValues(alpha: 0.8)
                          : Colors.grey[500],
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    levelDisplay,
                    style: TextStyle(
                      color: isActive ? Colors.white : Colors.black,
                      fontSize: levelDisplay.contains('-') ? 18 : 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildLessonGrid() {
    if (_levels.isEmpty) {
      return Center(
        child: Text(
          'No listening levels available yet.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final level = _selectedLevel;
    if (level == null) {
      return const Center(child: AppProgressIndicator());
    }

    if (_isLoadingLessons && _selectedLessons.isEmpty) {
      return const Center(child: AppProgressIndicator());
    }

    if (_lessonError != null && _selectedLessons.isEmpty) {
      return Center(
        child: AppCard(
          variant: AppCardVariant.flat,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.error),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Failed to load lessons',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                _lessonError ?? '',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Retry',
                onPressed: () => _loadLessonsForLevel(level, force: true),
                variant: AppButtonVariant.primary,
              ),
            ],
          ),
        ),
      );
    }

    final lessons = _selectedLessons;
    if (lessons.isEmpty) {
      return Center(
        child: Text(
          'Level has no listening lessons yet.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.9,
      ),
      itemCount: lessons.length,
      itemBuilder: (context, index) {
        final lesson = lessons[index];
        return HubCardEntrance(
          index: index,
          child: _ListeningLessonCard(
            lessonNumber: lesson.lessonNumber,
            range: lesson.range,
            durationLabel: _formatDuration(lesson.durationSec),
            questionLabel: '${lesson.questionCount}Q',
            avatarPath: _avatarForPersona(lesson.personaId),
            onTap: () => _openLesson(lesson),
          ),
        );
      },
    );
  }

  String _formatDuration(int durationSec) {
    if (durationSec <= 0) return '2m';
    if (durationSec % 60 == 0) return '${durationSec ~/ 60}m';
    return '${(durationSec / 60).toStringAsFixed(1)}m';
  }

  String _avatarForPersona(String personaId) {
    final key = personaId.trim();
    if (key.isEmpty) return PersonaAvatars.defaultAssistant;
    final missionAsset = PersonaAvatars.missionPersonaAsset[key];
    if (missionAsset != null) return missionAsset;
    final profileAsset = PersonaAvatars.profileAsset[key];
    if (profileAsset != null) return profileAsset;
    return PersonaAvatars.defaultAssistant;
  }
}

class _ListeningLessonCard extends StatelessWidget {
  final int lessonNumber;
  final String range;
  final String durationLabel;
  final String questionLabel;
  final String avatarPath;
  final VoidCallback onTap;

  const _ListeningLessonCard({
    required this.lessonNumber,
    required this.range,
    required this.durationLabel,
    required this.questionLabel,
    required this.avatarPath,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey[200]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: _LessonAvatar(assetPath: avatarPath, size: 34),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.2),
                    ),
                    child: const Icon(
                      Icons.volume_up_rounded,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'LESSON $lessonNumber',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              range,
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '$durationLabel • $questionLabel',
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LessonAvatar extends StatelessWidget {
  const _LessonAvatar({required this.assetPath, this.size = 34});

  final String assetPath;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          errorBuilder: (context, _, __) =>
              Image.asset(PersonaAvatars.defaultAssistant, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
