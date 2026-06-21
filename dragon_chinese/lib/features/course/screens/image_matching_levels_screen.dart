import 'package:flutter/material.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/design_system/design_system.dart';
import 'package:dragon_chinese/features/course/screens/image_matching_game_screen.dart';
import 'package:dragon_chinese/features/course/services/skill_service.dart';

class ImageMatchingLevelsScreen extends StatefulWidget {
  final String sourceLang;
  final String targetLang;
  const ImageMatchingLevelsScreen({
    super.key,
    this.sourceLang = 'en',
    this.targetLang = AppConfig.targetLang,
  });

  @override
  State<ImageMatchingLevelsScreen> createState() =>
      _ImageMatchingLevelsScreenState();
}

class _ImageMatchingLevelsScreenState extends State<ImageMatchingLevelsScreen> {
  List<SkillGroup> _levelStats = [];
  final Map<int, int> _imageWordCountByLevel = <int, int>{};
  final Set<int> _loadingCounts = <int>{};
  bool _isLoading = true;
  String? _errorMessage;
  int? _selectedLevel;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final stats = await SkillService().fetchSkillStats(
        widget.targetLang,
        sourceLang: widget.sourceLang,
      );
      if (!mounted) return;
      final sorted = stats..sort((a, b) => a.level.compareTo(b.level));
      final selected = _resolveSelectedLevel(
        selectedLevel: _selectedLevel,
        levels: sorted,
      );
      setState(() {
        _levelStats = sorted;
        _selectedLevel = selected;
        _isLoading = false;
      });
      if (selected != null) {
        await _loadImageCountForLevel(selected);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _levelStats = [];
        _selectedLevel = null;
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  int? _resolveSelectedLevel({
    required int? selectedLevel,
    required List<SkillGroup> levels,
  }) {
    if (levels.isEmpty) return null;
    if (selectedLevel == null) return levels.first.level;
    final exists = levels.any((l) => l.level == selectedLevel);
    return exists ? selectedLevel : levels.first.level;
  }

  Future<void> _loadImageCountForLevel(int level) async {
    if (_imageWordCountByLevel.containsKey(level) ||
        _loadingCounts.contains(level)) {
      return;
    }
    setState(() => _loadingCounts.add(level));
    try {
      final words = await SkillService().fetchImageVocabulary(
        level,
        sourceLang: widget.sourceLang,
        targetLang: widget.targetLang,
      );
      if (!mounted) return;
      setState(() {
        _imageWordCountByLevel[level] = words.length;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _imageWordCountByLevel[level] = 0;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingCounts.remove(level));
      }
    }
  }

  SkillGroup? get _selectedGroup {
    final selected = _selectedLevel;
    if (selected == null) return null;
    for (final group in _levelStats) {
      if (group.level == selected) return group;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Image Matching Hub',
      subtitle: 'Levels and sets',
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
                    title: 'Failed to load image matching levels',
                    subtitle: _errorMessage,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  AppButton(
                    label: 'Retry',
                    onPressed: _loadStats,
                    variant: AppButtonVariant.primary,
                  ),
                ],
              ),
            ),
          if (_levelStats.isNotEmpty) ...[
            _buildLevelSelector(),
            const Divider(height: 1),
          ],
          Expanded(
            child: _isLoading
                ? const Center(child: AppProgressIndicator())
                : _buildSetsGrid(),
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
        itemCount: _levelStats.length,
        itemBuilder: (context, index) {
          final group = _levelStats[index];
          final level = group.level;
          final isActive = selectedLevel == level;
          final levelDisplay = AppConfig.levelDisplayFromLabel(
            group.label,
            level,
          );
          return GestureDetector(
            onTap: () {
              setState(() => _selectedLevel = level);
              _loadImageCountForLevel(level);
            },
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

  Widget _buildSetsGrid() {
    if (_levelStats.isEmpty) {
      return Center(
        child: Text(
          'No image-matching levels available yet.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final group = _selectedGroup;
    if (group == null) {
      return const Center(child: AppProgressIndicator());
    }

    final level = group.level;
    final isLoadingCount = _loadingCounts.contains(level);
    final imageWordCount = _imageWordCountByLevel[level] ?? 0;

    if (isLoadingCount) {
      return const Center(child: AppProgressIndicator());
    }

    if (imageWordCount <= 0) {
      return Center(
        child: AppCard(
          variant: AppCardVariant.flat,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.image_not_supported_outlined, size: 30),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'No image sets ready for this level yet.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Refresh',
                onPressed: () => _loadImageCountForLevel(level),
                variant: AppButtonVariant.secondary,
              ),
            ],
          ),
        ),
      );
    }

    const int setSize = 10;
    final int setCount = (imageWordCount / setSize).ceil();

    return GridView.builder(
      padding: const EdgeInsets.all(20),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.9,
      ),
      itemCount: setCount,
      itemBuilder: (context, index) {
        final setNum = index + 1;
        final start = (index * setSize) + 1;
        final end = ((index + 1) * setSize) > imageWordCount
            ? imageWordCount
            : ((index + 1) * setSize);
        return _SetBatchCard(
          setNumber: setNum,
          range: '$start-$end',
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ImageMatchingGameScreen(
                  level: group.level,
                  setIndex: index,
                  sourceLang: widget.sourceLang,
                  targetLang: widget.targetLang,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SetBatchCard extends StatelessWidget {
  final int setNumber;
  final String range;
  final VoidCallback onTap;

  const _SetBatchCard({
    required this.setNumber,
    required this.range,
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
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.jade.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.image_search_rounded,
                color: AppColors.jadeDark,
                size: 24,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'SET $setNumber',
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
          ],
        ),
      ),
    );
  }
}
