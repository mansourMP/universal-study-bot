import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/colors.dart';
import 'package:dragon_chinese/features/course/services/skill_service.dart';

/// Quick Study Card - Launch batch learning sessions
class QuickStudyCard extends StatefulWidget {
  const QuickStudyCard({super.key});

  @override
  State<QuickStudyCard> createState() => _QuickStudyCardState();
}

class _QuickStudyCardState extends State<QuickStudyCard> {
  final SkillService _skillService = SkillService();
  bool _loading = false;

  Future<void> _startQuickStudy() async {
    setState(() => _loading = true);
    try {
      final session = await _skillService.startQuickStudySession(
        unitId: 'UNIT_HSK1_001', // Default to first unit for now
        wordCount: 5,
      );
      if (!mounted) return;
      Navigator.pushNamed(context, '/quick-study-intro', arguments: session);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: _loading ? null : _startQuickStudy,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Row(
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.bolt,
                  size: 32,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),

              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Study',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Learn 5 words in one session',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),

              // Loading or arrow
              if (_loading)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 20,
                  color: AppColors.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
