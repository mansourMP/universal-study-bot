import 'package:flutter/material.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/design_system/design_system.dart';
import 'package:dragon_chinese/features/course/services/skill_service.dart';
import 'package:dragon_chinese/features/course/screens/vocabulary_practice_screen.dart';
import 'package:dragon_chinese/features/course/widgets/hub_card_entrance.dart';

class VocabularyLevelsScreen extends StatefulWidget {
  final String sourceLang;
  final String targetLang;
  const VocabularyLevelsScreen({
    super.key,
    this.sourceLang = 'en',
    this.targetLang = AppConfig.targetLang,
  });

  @override
  State<VocabularyLevelsScreen> createState() => _VocabularyLevelsScreenState();
}

class _VocabularyLevelsScreenState extends State<VocabularyLevelsScreen> {
  int? _selectedLevel;
  List<SkillGroup> _levels = [];
  bool _isLoading = true;
  String? _errorMessage;

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
      setState(() {
        _levels = stats..sort((a, b) => a.level.compareTo(b.level));
        _selectedLevel = _resolveSelectedLevel(
          selectedLevel: _selectedLevel,
          levels: _levels,
        );
        _isLoading = false;
      });
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

  int? _resolveSelectedLevel({
    required int? selectedLevel,
    required List<SkillGroup> levels,
  }) {
    if (levels.isEmpty) return null;
    if (selectedLevel == null) return levels.first.level;
    final exists = levels.any((l) => l.level == selectedLevel);
    return exists ? selectedLevel : levels.first.level;
  }

  SkillGroup? get _selectedGroup {
    final level = _selectedLevel;
    if (level == null) return null;
    for (final item in _levels) {
      if (item.level == level) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Vocabulary Hub',
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
                    title: 'Failed to load vocabulary stats',
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
          if (_levels.isNotEmpty) ...[
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
            onTap: () => setState(() => _selectedLevel = level),
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
    if (_levels.isEmpty) {
      return Center(
        child: Text(
          'No vocabulary levels available yet.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    final stat = _selectedGroup;
    if (stat == null) {
      return const Center(child: AppProgressIndicator());
    }

    final int setSize = 20;
    final int setCount = (stat.count / setSize).ceil();
    final int totalWords = stat.count;

    if (setCount <= 0) {
      return Center(
        child: Text(
          'Level has no words yet.',
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
      itemCount: setCount,
      itemBuilder: (context, index) {
        final setNum = index + 1;
        final start = index * setSize + 1;
        final end = ((index + 1) * setSize) > totalWords
            ? totalWords
            : ((index + 1) * setSize);
        final remaining = totalWords - (index * setSize);
        final limit = remaining >= setSize ? setSize : remaining;
        return HubCardEntrance(
          index: index,
          child: _SetBatchCard(
            setNumber: setNum,
            range: '$start-$end',
            onTap: () {
              if (limit <= 0) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VocabularyPracticeScreen(
                    level: stat.level,
                    offset: index * setSize,
                    limit: limit,
                    setTitle: 'Set $setNum',
                    sourceLang: widget.sourceLang,
                    targetLang: widget.targetLang,
                  ),
                ),
              );
            },
          ),
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
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.style_rounded,
                color: AppColors.primary,
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
