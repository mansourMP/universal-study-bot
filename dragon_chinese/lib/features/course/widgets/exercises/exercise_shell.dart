import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dragon_chinese/design_system/exercise_theme.dart';
import 'package:dragon_chinese/design_system/pressable_keycap.dart';
import 'package:dragon_chinese/features/course/widgets/exercises/exercise_feedback_banner.dart';

/// The premium unified shell for all Practice exercises.
/// Handles Header, Progress, Scrolling Content, and the Fixed Footer.
class ExerciseShell extends StatefulWidget {
  final int index;
  final int total;
  final String? sectionLabel;
  final String? skillLabel;
  final IconData? skillIcon;
  final String? instruction;
  final String? subInstruction;
  final String? levelLabel;
  final int attemptsRemaining;
  final int attemptsTotal;
  final bool isAnswered;
  final bool isCorrect;
  final bool isReady;
  final int? timerRemainingSec;
  final int? timerTotalSec;
  final Widget content;
  final Widget? mediaSlot;
  final String? explainLabel;
  final VoidCallback? onExplain;
  final VoidCallback? onToggleSecondary;
  final bool showSecondaryToggle;
  final bool secondaryToggleActive;
  final String secondaryToggleLabel;
  final bool showSettingsMenu;
  final VoidCallback? onOpenSettings;
  final String? hint;
  final String? revealText;
  final String Function()? hintBuilder;
  final String Function()? revealBuilder;
  final String? primaryLabelOverride;
  final VoidCallback? onPrimaryOverride;
  final bool? primaryEnabledOverride;
  final bool hideFooter;
  final bool bodyScrollable;
  final VoidCallback onCheck;
  final VoidCallback onContinue;
  final VoidCallback onTryAgain;
  final VoidCallback? onClose;

  const ExerciseShell({
    super.key,
    required this.index,
    required this.total,
    required this.attemptsRemaining,
    required this.attemptsTotal,
    required this.isAnswered,
    required this.isCorrect,
    required this.isReady,
    required this.content,
    required this.onCheck,
    required this.onContinue,
    required this.onTryAgain,
    this.sectionLabel,
    this.skillLabel,
    this.skillIcon,
    this.instruction,
    this.subInstruction,
    this.levelLabel,
    this.timerRemainingSec,
    this.timerTotalSec,
    this.mediaSlot,
    this.explainLabel,
    this.onExplain,
    this.onToggleSecondary,
    this.showSecondaryToggle = false,
    this.secondaryToggleActive = false,
    this.secondaryToggleLabel = 'P',
    this.showSettingsMenu = false,
    this.onOpenSettings,
    this.hint,
    this.revealText,
    this.hintBuilder,
    this.revealBuilder,
    this.primaryLabelOverride,
    this.onPrimaryOverride,
    this.primaryEnabledOverride,
    this.hideFooter = false,
    this.bodyScrollable = true,
    this.onClose,
  });

  @override
  State<ExerciseShell> createState() => _ExerciseShellState();
}

class _ExerciseShellState extends State<ExerciseShell> {
  int get index => widget.index;
  int get total => widget.total;
  String? get sectionLabel => widget.sectionLabel;
  String? get skillLabel => widget.skillLabel;
  IconData? get skillIcon => widget.skillIcon;
  String? get instruction => widget.instruction;
  String? get subInstruction => widget.subInstruction;
  String? get levelLabel => widget.levelLabel;
  int get attemptsRemaining => widget.attemptsRemaining;
  int get attemptsTotal => widget.attemptsTotal;
  bool get isAnswered => widget.isAnswered;
  bool get isCorrect => widget.isCorrect;
  bool get isReady => widget.isReady;
  int? get timerRemainingSec => widget.timerRemainingSec;
  int? get timerTotalSec => widget.timerTotalSec;
  Widget get content => widget.content;
  Widget? get mediaSlot => widget.mediaSlot;
  String? get explainLabel => widget.explainLabel;
  VoidCallback? get onExplain => widget.onExplain;
  VoidCallback? get onToggleSecondary => widget.onToggleSecondary;
  bool get showSecondaryToggle => widget.showSecondaryToggle;
  bool get secondaryToggleActive => widget.secondaryToggleActive;
  String get secondaryToggleLabel => widget.secondaryToggleLabel;
  bool get showSettingsMenu => widget.showSettingsMenu;
  VoidCallback? get onOpenSettings => widget.onOpenSettings;
  String? get hint => widget.hint;
  String? get revealText => widget.revealText;
  String Function()? get hintBuilder => widget.hintBuilder;
  String Function()? get revealBuilder => widget.revealBuilder;
  String? get primaryLabelOverride => widget.primaryLabelOverride;
  VoidCallback? get onPrimaryOverride => widget.onPrimaryOverride;
  bool? get primaryEnabledOverride => widget.primaryEnabledOverride;
  bool get hideFooter => widget.hideFooter;
  bool get bodyScrollable => widget.bodyScrollable;
  VoidCallback get onCheck => widget.onCheck;
  VoidCallback get onContinue => widget.onContinue;
  VoidCallback get onTryAgain => widget.onTryAgain;
  VoidCallback? get onClose => widget.onClose;

  Timer? _hapticTimer;

  @override
  void dispose() {
    _hapticTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ExerciseShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (isAnswered && !oldWidget.isAnswered) {
      if (isCorrect) {
        // Success: Double light tap
        HapticFeedback.lightImpact();
        _hapticTimer?.cancel();
        _hapticTimer = Timer(const Duration(milliseconds: 75), () {
          if (mounted) HapticFeedback.lightImpact();
        });
      } else {
        // Error: Single medium impact
        HapticFeedback.mediumImpact();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    const contentMaxWidth = 760.0;
    // Keep answer interactions in a comfortable thumb zone.
    final answerZoneTopOffset = hideFooter
        ? 8.0
        : (screenHeight * 0.055).clamp(18.0, 44.0).toDouble();

    return Scaffold(
      backgroundColor: ExerciseThemeTokens.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                child: _buildTopBar(context),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: contentMaxWidth),
                  child: bodyScrollable
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ExerciseThemeTokens.pageMargin,
                            vertical: ExerciseThemeTokens.gapMedium,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (mediaSlot != null) ...[
                                AnimatedSwitcher(
                                  duration: ExerciseThemeTokens.motionNormal,
                                  switchInCurve:
                                      ExerciseThemeTokens.motionCurve,
                                  switchOutCurve:
                                      ExerciseThemeTokens.motionCurve,
                                  child: KeyedSubtree(
                                    key: const ValueKey('media-slot'),
                                    child: mediaSlot!,
                                  ),
                                ),
                                const SizedBox(
                                  height: ExerciseThemeTokens.gapMedium,
                                ),
                              ],
                              _buildInstructionHeader(),
                              const SizedBox(
                                height: ExerciseThemeTokens.gapMedium,
                              ),
                              SizedBox(height: answerZoneTopOffset),
                              content,
                              // Keep options visually close to footer CTA.
                              const SizedBox(height: 12),
                            ],
                          ),
                        )
                      : Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: ExerciseThemeTokens.pageMargin,
                            vertical: ExerciseThemeTokens.gapMedium,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (mediaSlot != null) ...[
                                AnimatedSwitcher(
                                  duration: ExerciseThemeTokens.motionNormal,
                                  switchInCurve:
                                      ExerciseThemeTokens.motionCurve,
                                  switchOutCurve:
                                      ExerciseThemeTokens.motionCurve,
                                  child: KeyedSubtree(
                                    key: const ValueKey('media-slot'),
                                    child: mediaSlot!,
                                  ),
                                ),
                                const SizedBox(
                                  height: ExerciseThemeTokens.gapMedium,
                                ),
                              ],
                              _buildInstructionHeader(),
                              const SizedBox(
                                height: ExerciseThemeTokens.gapMedium,
                              ),
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(
                                    top: answerZoneTopOffset,
                                  ),
                                  child: content,
                                ),
                              ),
                              // Fixed compact gap so choice area sits just above CTA.
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            if (!hideFooter) _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          Material(
            color: ExerciseThemeTokens.surfaceSubtle,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onClose ?? () => Navigator.pop(context),
              child: const SizedBox(
                width: 36,
                height: 36,
                child: Icon(
                  Icons.close,
                  color: ExerciseThemeTokens.textSecondary,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: LinearProgressIndicator(
                value: total > 0 ? (index + 1) / total : 0,
                minHeight: 5,
                backgroundColor: ExerciseThemeTokens.surfaceMuted,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  ExerciseThemeTokens.accent,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Timer shown only in Exam mode (when timerRemainingSec is provided)
          if (timerRemainingSec != null) ...[
            _buildTimerPill(),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  // Timer pill for Exam mode only
  Widget _buildTimerPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: ExerciseThemeTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(ExerciseThemeTokens.pillRadius),
      ),
      child: Text(
        'Time left: ${timerRemainingSec}s',
        style: ExerciseThemeTokens.caption,
      ),
    );
  }

  Widget _buildInstructionHeader() {
    final hasActions =
        onExplain != null || showSecondaryToggle || showSettingsMenu;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (instruction != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  instruction!,
                  style: ExerciseThemeTokens.promptTitle,
                ),
              ),
              if (hasActions) ...[
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onExplain != null)
                      _buildHeaderChip(
                        label: '!',
                        isActive: false,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onExplain?.call();
                        },
                      ),
                    if (showSecondaryToggle) ...[
                      if (onExplain != null) const SizedBox(width: 6),
                      _buildHeaderChip(
                        label: secondaryToggleLabel.isEmpty
                            ? 'P'
                            : secondaryToggleLabel
                                  .substring(0, 1)
                                  .toUpperCase(),
                        isActive: secondaryToggleActive,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onToggleSecondary?.call();
                        },
                      ),
                    ],
                    if (showSettingsMenu) ...[
                      if (onExplain != null || showSecondaryToggle)
                        const SizedBox(width: 6),
                      _buildHeaderChip(
                        icon: Icons.more_horiz_rounded,
                        isActive: false,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          if (onOpenSettings != null) {
                            onOpenSettings!.call();
                            return;
                          }
                          _showDefaultSettingsMenu(context);
                        },
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        if (subInstruction != null) ...[
          const SizedBox(height: 4),
          Text(subInstruction!, style: ExerciseThemeTokens.caption),
        ],
      ],
    );
  }

  Widget _buildHeaderChip({
    String? label,
    IconData? icon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    final activeColor = ExerciseThemeTokens.accent;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        curve: Curves.easeOutCubic,
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive
              ? activeColor.withValues(alpha: 0.14)
              : ExerciseThemeTokens.surfaceMuted,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isActive ? activeColor : ExerciseThemeTokens.border,
          ),
        ),
        child: icon != null
            ? Icon(
                icon,
                size: 13,
                color: isActive ? activeColor : ExerciseThemeTokens.textMuted,
              )
            : Text(
                label ?? '',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isActive ? activeColor : ExerciseThemeTokens.textMuted,
                ),
              ),
      ),
    );
  }

  void _showDefaultSettingsMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: ExerciseThemeTokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: ExerciseThemeTokens.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Exercise settings',
                  style: ExerciseThemeTokens.promptBody.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                if (showSecondaryToggle && onToggleSecondary != null)
                  _settingsRow(
                    title: 'Show pinyin',
                    trailing: Switch(
                      value: secondaryToggleActive,
                      onChanged: (_) {
                        onToggleSecondary?.call();
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
                _settingsRow(
                  title: 'Show translation',
                  subtitle: 'Coming soon',
                  trailing: const Icon(
                    Icons.lock_outline_rounded,
                    color: ExerciseThemeTokens.textMuted,
                    size: 18,
                  ),
                ),
                _settingsRow(
                  title: 'Show grammar hints',
                  subtitle: 'Coming soon',
                  trailing: const Icon(
                    Icons.lock_outline_rounded,
                    color: ExerciseThemeTokens.textMuted,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _settingsRow({
    required String title,
    String? subtitle,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: ExerciseThemeTokens.surfaceSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ExerciseThemeTokens.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: ExerciseThemeTokens.optionText.copyWith(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: ExerciseThemeTokens.caption.copyWith(
                        color: ExerciseThemeTokens.textMuted,
                      ),
                    ),
                ],
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  // _buildFeedbackCard moved to inline _buildMinimalFeedback or removed

  Widget _buildFooter(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final bottomPad = bottomInset > 0 ? bottomInset + 10.0 : 18.0;

    // Determine button state
    String label = 'Check';
    VoidCallback? action = onCheck;
    bool isEnabled = isReady;

    if (primaryLabelOverride != null) {
      label = primaryLabelOverride!;
      action = onPrimaryOverride;
      isEnabled = primaryEnabledOverride ?? true;
    } else {
      if (isAnswered) {
        if (isCorrect || attemptsRemaining == 0) {
          label = 'Continue';
          action = onContinue;
          isEnabled = true;
        } else {
          label = 'Try Again';
          action = onTryAgain;
          isEnabled = true;
        }
      }
    }

    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, bottomPad),
      decoration: const BoxDecoration(
        color: ExerciseThemeTokens.surface,
        border: Border(
          top: BorderSide(color: ExerciseThemeTokens.border, width: 1),
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x10000000),
            blurRadius: 12,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Align(
        alignment: Alignment.center,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                width: double.infinity,
                child: PressableCtaButton(
                  label: label,
                  onTap: isEnabled ? action : null,
                  enabled: isEnabled,
                ),
              ),
              if (isAnswered)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 62,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: ExerciseThemeTokens.motionNormal,
                          switchInCurve: ExerciseThemeTokens.motionCurve,
                          switchOutCurve: ExerciseThemeTokens.motionCurve,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SizeTransition(
                                  sizeFactor: animation,
                                  axisAlignment: -1,
                                  child: child,
                                ),
                              ),
                          child: _buildMinimalFeedback(),
                        ),
                        if (!isCorrect && attemptsRemaining > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: List.generate(attemptsTotal, (i) {
                                final used = attemptsTotal - attemptsRemaining;
                                final isFilled = i < used;
                                return Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: isFilled
                                        ? ExerciseThemeTokens.textMuted
                                        : ExerciseThemeTokens.surfaceMuted,
                                    border: Border.all(
                                      color: ExerciseThemeTokens.border,
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMinimalFeedback() {
    final bool isRetry = !isCorrect && attemptsRemaining > 0;

    String title;
    String? body;
    ExerciseFeedbackTone tone;
    IconData? icon;

    if (isCorrect) {
      title = 'Correct';
      tone = ExerciseFeedbackTone.success;
    } else if (isRetry) {
      title = 'Not quite';
      tone = ExerciseFeedbackTone.info;
      icon = Icons.info_rounded;
      if (attemptsRemaining == 1) {
        body = hintBuilder?.call() ?? hint ?? 'One last try!';
      }
    } else {
      title = 'Incorrect';
      tone = ExerciseFeedbackTone.error;
      body = revealBuilder?.call() ?? revealText;
    }

    return ExerciseFeedbackBanner(
      key: ValueKey('footer-feedback-$title-$body'),
      tone: tone,
      title: title,
      body: body,
      icon: icon,
    );
  }
}

class ExerciseUnavailableCard extends StatelessWidget {
  final String message;

  const ExerciseUnavailableCard({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: ExerciseThemeTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(ExerciseThemeTokens.cardRadius),
        border: Border.all(
          color: ExerciseThemeTokens.border,
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.build_circle_outlined,
            size: 48,
            color: ExerciseThemeTokens.textMuted,
          ),
          const SizedBox(height: 16),
          Text(
            'Content Unavailable',
            style: ExerciseThemeTokens.promptTitle.copyWith(
              color: ExerciseThemeTokens.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: ExerciseThemeTokens.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class ExerciseLoadingSkeleton extends StatelessWidget {
  const ExerciseLoadingSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ExerciseThemeTokens.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(ExerciseThemeTokens.pageMargin),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              _box(height: 200, width: double.infinity),
              const SizedBox(height: 24),
              _box(height: 24, width: 150),
              const SizedBox(height: 16),
              _box(height: 40, width: double.infinity),
              const SizedBox(height: 32),
              _box(height: 60, width: double.infinity),
              const SizedBox(height: 12),
              _box(height: 60, width: double.infinity),
              const SizedBox(height: 12),
              _box(height: 60, width: double.infinity),
            ],
          ),
        ),
      ),
    );
  }

  Widget _box({required double height, required double width}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: ExerciseThemeTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(ExerciseThemeTokens.radiusMd),
      ),
    );
  }
}
