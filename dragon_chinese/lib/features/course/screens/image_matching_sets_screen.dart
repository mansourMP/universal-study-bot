import 'package:flutter/material.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/features/course/screens/image_matching_game_screen.dart';

class ImageMatchingSetsScreen extends StatelessWidget {
  final int level;
  final String sourceLang;
  final String targetLang;

  const ImageMatchingSetsScreen({
    super.key,
    required this.level,
    required this.sourceLang,
    this.targetLang = AppConfig.targetLang,
  });

  @override
  Widget build(BuildContext context) {
    // For now, let's show a few sets. In production, this would be dynamic.
    final int setCount = 5;

    return Scaffold(
      backgroundColor: const Color(0xFFF2F2F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        title: Text('${AppConfig.levelPrefix} $level Sets'),
        elevation: 0,
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: setCount,
        itemBuilder: (context, index) {
          return _SetButton(
            label: '${index + 1}',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ImageMatchingGameScreen(
                    level: level,
                    setIndex: index,
                    sourceLang: sourceLang,
                    targetLang: targetLang,
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

class _SetButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _SetButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ),
      ),
    );
  }
}
