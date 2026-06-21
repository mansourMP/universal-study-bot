import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/design_system.dart';
import 'package:dragon_chinese/features/course/screens/vocabulary_practice_screen.dart';

class VocabularySetsScreen extends StatelessWidget {
  final int level;
  final int totalWords;
  final int setSize = 20;
  final String sourceLang;

  const VocabularySetsScreen({
    super.key,
    required this.level,
    required this.totalWords,
    this.sourceLang = 'en',
  });

  @override
  Widget build(BuildContext context) {
    final int setCount = (totalWords / setSize).ceil();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('HSK $level Sets'),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(DragonSpacing.md),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: DragonSpacing.md,
          mainAxisSpacing: DragonSpacing.md,
          childAspectRatio: 1.0,
        ),
        itemCount: setCount,
        itemBuilder: (context, index) {
          final setIndex = index + 1;
          final startWord = index * setSize + 1;
          final endWord = (index + 1) * setSize;
          final displayEnd = endWord > totalWords ? totalWords : endWord;

          return _SetCard(
            setIndex: setIndex,
            range: '$startWord-$displayEnd',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VocabularyPracticeScreen(
                    level: level,
                    offset: index * setSize,
                    limit: setSize,
                    setTitle: 'Set $setIndex',
                    sourceLang: sourceLang,
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SetCard extends StatelessWidget {
  final int setIndex;
  final String range;
  final VoidCallback onTap;

  const _SetCard({
    required this.setIndex,
    required this.range,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DragonSpacing.radiusMd),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DragonSpacing.radiusMd),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.style, color: AppColors.primary),
            ),
            const SizedBox(height: 8),
            Text(
              'Set $setIndex',
              style: DragonTypography.titleSmall.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              range,
              style: DragonTypography.labelSmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
