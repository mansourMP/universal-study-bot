import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dragon_chinese/design_system/design_system.dart';
import 'package:dragon_chinese/features/course/services/goal_profile.dart';
import 'package:dragon_chinese/features/course/services/goal_profile_store.dart';

class GoalSelectionScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const GoalSelectionScreen({super.key, required this.onComplete});

  @override
  State<GoalSelectionScreen> createState() => _GoalSelectionScreenState();
}

class _GoalSelectionScreenState extends State<GoalSelectionScreen>
    with SingleTickerProviderStateMixin {
  GoalType? _selectedGoal;
  bool _isSubmitting = false;
  late AnimationController _pulseController;

  final List<_GoalOption> _goals = const [
    _GoalOption(
      id: GoalType.exam,
      title: 'EXAM FOCUS',
      icon: Icons.fact_check_rounded,
      desc: 'HSK-aligned reading, cloze, and accuracy drills.',
    ),
    _GoalOption(
      id: GoalType.speaking,
      title: 'SPEAKING FOCUS',
      icon: Icons.mic_rounded,
      desc: 'Conversation fluency and response practice.',
    ),
    _GoalOption(
      id: GoalType.professional,
      title: 'PROFESSIONAL',
      icon: Icons.work_rounded,
      desc: 'Workplace context, meetings, and formal tone.',
    ),
    _GoalOption(
      id: GoalType.travel,
      title: 'TRAVEL',
      icon: Icons.flight_takeoff_rounded,
      desc: 'Transit, directions, and practical travel language.',
    ),
    _GoalOption(
      id: GoalType.casual,
      title: 'CASUAL',
      icon: Icons.coffee_rounded,
      desc: 'Everyday conversations and daily life.',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadSelection();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _loadSelection() async {
    final saved = await GoalProfileStore.getGoal();
    if (mounted) {
      setState(() => _selectedGoal = saved ?? GoalProfiles.defaultProfile.goal);
    }
  }

  Future<void> _submitGoal() async {
    if (_selectedGoal == null) return;
    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();
    await GoalProfileStore.setGoal(_selectedGoal!);
    if (mounted) {
      setState(() => _isSubmitting = false);
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PathThemeTokens.ink900,
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                PathThemeTokens.ink900,
                PathThemeTokens.ink700,
              ],
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 32),
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: PathThemeTokens.accentRed
                              .withOpacity(0.18 * _pulseController.value),
                          blurRadius: 18 + (8 * _pulseController.value),
                          spreadRadius: 2 + (4 * _pulseController.value),
                        ),
                      ],
                      gradient: RadialGradient(
                        colors: [
                          PathThemeTokens.accentRed,
                          PathThemeTokens.primaryDark,
                        ],
                      ),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: Colors.white,
                      size: 30,
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              Text(
                'SELECT YOUR GOAL',
                style: DragonTypography.titleMedium.copyWith(
                  color: Colors.white,
                  letterSpacing: 3.0,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Focus your practice without changing the HSK spine.',
                style: DragonTypography.labelMedium.copyWith(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.95,
                  ),
                  itemCount: _goals.length,
                  itemBuilder: (context, index) {
                    final goal = _goals[index];
                    final isSelected = _selectedGoal == goal.id;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _selectedGoal = goal.id);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withOpacity(0.08)
                              : Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: isSelected
                                ? PathThemeTokens.accentRed
                                : Colors.white10,
                            width: 1.2,
                          ),
                          boxShadow:
                              isSelected ? [PathThemeTokens.shadowMd] : null,
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              goal.icon,
                              size: 28,
                              color: isSelected
                                  ? PathThemeTokens.accentGold
                                  : Colors.white70,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              goal.title,
                              textAlign: TextAlign.center,
                              style: DragonTypography.labelMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              goal.desc,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white70,
                                height: 1.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24.0),
                child: _isSubmitting
                    ? const CircularProgressIndicator(color: Colors.white)
                    : GameButton(
                        text: 'START WITH THIS GOAL',
                        onPressed: _selectedGoal != null ? _submitGoal : null,
                        variant: GameButtonVariant.primary,
                        customColor: PathThemeTokens.accentRed,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalOption {
  final GoalType id;
  final String title;
  final IconData icon;
  final String desc;

  const _GoalOption({
    required this.id,
    required this.title,
    required this.icon,
    required this.desc,
  });
}
