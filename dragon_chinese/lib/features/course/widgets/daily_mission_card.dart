import 'package:flutter/material.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/design_system/design_system.dart';
import 'package:dragon_chinese/features/course/models/brain_models.dart';
import 'package:dragon_chinese/features/course/screens/brain_exercise_runner_screen.dart';
import 'package:dragon_chinese/features/course/services/brain_service.dart';
import 'package:dragon_chinese/features/course/widgets/path_components.dart';

class DailyMissionCard extends StatefulWidget {
  const DailyMissionCard({super.key});

  @override
  State<DailyMissionCard> createState() => _DailyMissionCardState();
}

class _DailyMissionCardState extends State<DailyMissionCard> {
  final BrainService _brainService = BrainService();
  BrainSummary? _summary;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchSummary();
  }

  Future<void> _fetchSummary() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final summary = await _brainService.getSummary(userId: AppConfig.userId);
      if (mounted) {
        setState(() {
          _summary = summary;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load mission data';
          _isLoading = false;
        });
      }
    }
  }

  void _onStartMission(BuildContext context, {String intent = 'daily'}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BrainExerciseRunnerScreen(
          intent: intent,
          onComplete: () {
            // Nothing specific needed here, as we refresh below
          },
        ),
      ),
    );
    // Refresh summary when returning
    _fetchSummary();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return _buildSkeleton();
    }
    if (_error != null) {
      return _buildError();
    }
    if (_summary == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: PathThemeTokens.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [PathThemeTokens.shadowMd],
        border: Border.all(color: PathThemeTokens.borderSubtle),
      ),
      child: Material(
        // For ink well
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildContent(),
              const SizedBox(height: 20),
              _buildAction(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return Container(
      height: 140,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: PathThemeTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SyncBanner(onRetry: _fetchSummary),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Icon(Icons.auto_awesome, color: PathThemeTokens.brandAccent, size: 24),
        const SizedBox(width: 8),
        const Text(
          'DAILY MISSION',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Color(0xFF6B7280),
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    // State 1: Resume
    if (_summary!.hasActiveMission) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mission in progress',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: PathThemeTokens.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Continue where you left off',
            style: TextStyle(fontSize: 14, color: PathThemeTokens.textSecondary),
          ),
        ],
      );
    }

    // State 2: Due
    if (_summary!.dueCount > 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_summary!.dueCount} items due',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: PathThemeTokens.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _summary!.reviewDueCount > 0
                ? '${_summary!.reviewDueCount} words related to past lessons'
                : '${_summary!.learnAvailableCount} new words available',
            style: const TextStyle(fontSize: 14, color: PathThemeTokens.textSecondary),
          ),
        ],
      );
    }

    // State 3: Caught Up
    final nextReview = _summary!.nextReviewAt;
    String timeStr = 'tomorrow';

    if (nextReview != null) {
      final local = nextReview.toLocal();
      final hour = local.hour.toString().padLeft(2, '0');
      final minute = local.minute.toString().padLeft(2, '0');
      timeStr = '$hour:$minute';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'You are caught up!',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: PathThemeTokens.success,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Next review available at $timeStr',
          style: const TextStyle(fontSize: 14, color: PathThemeTokens.textSecondary),
        ),
      ],
    );
  }

  Widget _buildAction() {
    if (_summary == null) return const SizedBox.shrink();

    // Resume
    if (_summary!.hasActiveMission) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _onStartMission(context, intent: 'daily'),
          icon: const Icon(Icons.play_arrow),
          label: const Text('RESUME MISSION'),
          style: ElevatedButton.styleFrom(
            backgroundColor: PathThemeTokens.brandAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
    }

    // Start Due
    if (_summary!.dueCount > 0) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => _onStartMission(context, intent: 'daily'),
          style: ElevatedButton.styleFrom(
            backgroundColor: PathThemeTokens.brandAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: const Text(
            'START MISSION',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
    }

    // Start Practice (Learn/Review) when caught up
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _onStartMission(context, intent: 'learn'),
            child: const Text('PRACTICE NEW'),
          ),
        ),
      ],
    );
  }
}
