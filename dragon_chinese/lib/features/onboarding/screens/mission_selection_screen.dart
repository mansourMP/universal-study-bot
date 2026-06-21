import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dragon_chinese/design_system/design_system.dart';
import 'package:dragon_chinese/core/utils/mission_prefs.dart';
import 'package:dragon_chinese/core/network/api_client.dart';
import 'package:dragon_chinese/core/net/endpoints.dart';
import 'package:dragon_chinese/core/net/api_result.dart';
import 'package:dragon_chinese/core/utils/app_log.dart';
import 'package:dragon_chinese/core/constants/persona_avatars.dart';

class MissionSelectionScreen extends StatefulWidget {
  final VoidCallback onComplete;
  const MissionSelectionScreen({super.key, required this.onComplete});

  @override
  State<MissionSelectionScreen> createState() => _MissionSelectionScreenState();
}

class _MissionSelectionScreenState extends State<MissionSelectionScreen>
    with SingleTickerProviderStateMixin {
  String? _selectedGoal;
  bool _isSubmitting = false;
  late AnimationController _pulseController;

  final List<Map<String, dynamic>> _missions = [
    {
      'id': 'hsk',
      'title': 'EXAM WARRIOR',
      'icon': Icons.psychology,
      'desc': 'Focus on HSK frequency & grammar.',
    },
    {
      'id': 'casual',
      'title': 'CASUAL EXPLORER',
      'icon': Icons.coffee,
      'desc': 'Hobbies, music, and daily habits.',
    },
    {
      'id': 'professional',
      'title': 'PROFESSIONAL',
      'icon': Icons.work,
      'desc': 'Negotiation, career & networking.',
    },
    {
      'id': 'survival',
      'title': 'SURVIVALIST',
      'icon': Icons.medical_services,
      'desc': 'Emergency, travel & basic needs.',
    },
    {
      'id': 'cultural',
      'title': 'CULTURALIST',
      'icon': Icons.auto_stories,
      'desc': 'History, idioms & literature.',
    },
    {
      'id': 'digital',
      'title': 'DIGITAL NOMAD',
      'icon': Icons.devices,
      'desc': 'Apps, tech & modern urban life.',
    },
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
    final saved = await MissionPrefs.getPersonaId();
    if (mounted) {
      setState(() => _selectedGoal = saved);
    }
  }

  Future<void> _submitGoal() async {
    if (_selectedGoal == null) return;
    setState(() => _isSubmitting = true);
    HapticFeedback.mediumImpact();

    try {
      await MissionPrefs.setPersonaId(_selectedGoal!);

      final api = ApiClient();
      final result = await api.postJsonResult(
        Endpoints.profileSetup,
        body: {'goal': _selectedGoal},
      );

      if (result is ApiFailure) {
        AppLog.e(
          'Server error during profile setup',
          error: (result as ApiFailure).message,
        );
      }

      // Proceed to app regardless of server success (offline-ish behavior for onboarding)
      widget.onComplete();
    } catch (e) {
      AppLog.e('Unexpected error during submission', error: e);
      widget.onComplete();
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
              colors: [PathThemeTokens.ink900, PathThemeTokens.ink700],
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 40),

              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: PathThemeTokens.accentRed.withValues(
                            alpha: 0.2 * _pulseController.value,
                          ),
                          blurRadius: 16 + (10 * _pulseController.value),
                          spreadRadius: 3 + (6 * _pulseController.value),
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

              const SizedBox(height: 28),
              Text(
                'SELECT YOUR MISSION',
                style: DragonTypography.titleMedium.copyWith(
                  color: Colors.white,
                  letterSpacing: 3.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a focus for your learning journey.',
                style: DragonTypography.labelMedium.copyWith(
                  color: Colors.white70,
                ),
              ),

              const SizedBox(height: 36),

              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    childAspectRatio: 0.92,
                  ),
                  itemCount: _missions.length,
                  itemBuilder: (context, index) {
                    final mission = _missions[index];
                    final isSelected = _selectedGoal == mission['id'];

                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _selectedGoal = mission['id']);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.white.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: isSelected
                                ? PathThemeTokens.accentRed
                                : Colors.white10,
                            width: 1.4,
                          ),
                          boxShadow: isSelected
                              ? [PathThemeTokens.shadowMd]
                              : null,
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _MissionAvatar(
                              assetPath: PersonaAvatars.mission(
                                mission['id'] as String?,
                              ),
                              highlighted: isSelected,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              mission['title'],
                              textAlign: TextAlign.center,
                              style: DragonTypography.labelMedium.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.6,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              mission['desc'],
                              textAlign: TextAlign.center,
                              style: TextStyle(
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
                        text: 'INITIALIZE PATH',
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

class _MissionAvatar extends StatelessWidget {
  const _MissionAvatar({
    required this.assetPath,
    required this.highlighted,
  });

  final String assetPath;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: highlighted ? PathThemeTokens.accentGold : Colors.white24,
          width: highlighted ? 2 : 1,
        ),
        boxShadow: highlighted ? [PathThemeTokens.shadowSm] : null,
      ),
      child: ClipOval(
        child: Image.asset(
          assetPath,
          fit: BoxFit.cover,
          errorBuilder: (context, _, __) => Container(
            color: Colors.white10,
            alignment: Alignment.center,
            child: const Icon(
              Icons.person_rounded,
              color: Colors.white70,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }
}
