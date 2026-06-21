import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dragon_chinese/design_system/exercise_theme.dart';

class PressableKeycap extends StatefulWidget {
  final double height;
  final double depth;
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final Color faceColor;
  final Color baseColor;
  final Color borderColor;
  final double borderWidth;
  final Color? baseBorderColor;
  final double? baseDarken;
  final double borderRadius;
  final BoxShape shape;

  const PressableKeycap({
    super.key,
    required this.height,
    required this.child,
    this.depth = ExerciseThemeTokens.keycapDepth,
    this.onTap,
    this.enabled = true,
    this.faceColor = ExerciseThemeTokens.surface,
    this.baseColor = ExerciseThemeTokens.surfaceMuted,
    this.borderColor = ExerciseThemeTokens.border,
    this.borderWidth = 1.0,
    this.baseBorderColor,
    this.baseDarken,
    this.borderRadius = ExerciseThemeTokens.radiusMd,
    this.shape = BoxShape.rectangle,
  });

  @override
  State<PressableKeycap> createState() => _PressableKeycapState();
}

class _PressableKeycapState extends State<PressableKeycap> {
  bool _pressed = false;

  void _tapDown(TapDownDetails details) {
    if (!widget.enabled || widget.onTap == null) return;
    HapticFeedback.selectionClick();
    setState(() => _pressed = true);
  }

  void _tapUp(TapUpDetails details) {
    if (!widget.enabled || widget.onTap == null) return;
    setState(() => _pressed = false);
    HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  void _tapCancel() {
    if (!widget.enabled) return;
    setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final double depth = widget.enabled ? widget.depth : 0.0;
    final double faceHeight = widget.height - widget.depth;

    final Color derivedBase = widget.baseDarken == null
        ? widget.baseColor
        : Color.alphaBlend(
            Colors.black.withValues(alpha: 0.3), // Solid darkening for 3D look
            widget.faceColor,
          );

    // For circles, create elliptical shape for isometric perspective
    final bool isCircle = widget.shape == BoxShape.circle;
    final BorderRadius effectiveRadius = isCircle
        ? BorderRadius.all(
            Radius.elliptical(widget.height / 2, widget.height * 0.4),
          )
        : BorderRadius.circular(widget.borderRadius);

    return GestureDetector(
      onTapDown: _tapDown,
      onTapUp: _tapUp,
      onTapCancel: _tapCancel,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        width: isCircle ? widget.height : null,
        height: widget.height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1. BASE layer (The Cylinder/Strip)
            Positioned(
              left: 0,
              right: 0,
              top: depth, // The base sits at the bottom
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: derivedBase,
                  borderRadius: effectiveRadius,
                  border: Border.all(
                    color: widget.baseBorderColor ?? widget.borderColor,
                    width: widget.borderWidth,
                  ),
                ),
              ),
            ),
            // 2. FACE layer (The Top)
            AnimatedPositioned(
              duration: _pressed
                  ? ExerciseThemeTokens.pressDuration
                  : ExerciseThemeTokens.releaseDuration,
              curve: _pressed
                  ? ExerciseThemeTokens.pressCurve
                  : ExerciseThemeTokens.releaseCurve,
              top: _pressed ? depth : 0,
              left: 0,
              right: 0,
              height: faceHeight,
              child: Container(
                decoration: BoxDecoration(
                  color: widget.faceColor,
                  borderRadius: effectiveRadius,
                  border: Border.all(
                    color: widget.borderColor,
                    width: widget.borderWidth,
                  ),
                ),
                child: Center(child: widget.child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A primary CTA button with keycap press feel.
class PressableCtaButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final Color? backgroundColor;
  final Color? textColor;

  const PressableCtaButton({
    super.key,
    required this.label,
    this.onTap,
    this.enabled = true,
    this.backgroundColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = enabled
        ? (backgroundColor ?? ExerciseThemeTokens.accent)
        : ExerciseThemeTokens.surfaceMuted;
    final baseColor = enabled
        ? ExerciseThemeTokens.accentHover
        : ExerciseThemeTokens.surfaceMuted;
    final labelColor = enabled
        ? (textColor ?? ExerciseThemeTokens.onAccent)
        : ExerciseThemeTokens.textMuted;

    return PressableKeycap(
      height: 56,
      depth: ExerciseThemeTokens.keycapDepth,
      onTap: onTap,
      enabled: enabled,
      faceColor: bgColor,
      baseColor: baseColor,
      borderColor: enabled ? baseColor : ExerciseThemeTokens.border,
      baseBorderColor: baseColor, // Solid base look
      baseDarken: ExerciseThemeTokens.keycapBaseDarken,
      borderRadius: ExerciseThemeTokens.buttonRadius,
      child: Text(
        label,
        style: ExerciseThemeTokens.ctaText.copyWith(color: labelColor),
      ),
    );
  }
}

/// A reusable option card with keycap feel.
class PressableOptionCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool enabled;
  final Color faceColor;
  final Color baseColor;
  final Color borderColor;
  final double borderWidth;
  final Color? baseBorderColor;
  final double? baseDarken;
  final double height;

  const PressableOptionCard({
    super.key,
    required this.child,
    required this.onTap,
    required this.enabled,
    required this.faceColor,
    required this.baseColor,
    required this.borderColor,
    this.borderWidth = 1.0,
    this.baseBorderColor,
    this.baseDarken,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return PressableKeycap(
      height: height,
      depth: ExerciseThemeTokens.keycapDepth,
      onTap: onTap,
      enabled: enabled,
      faceColor: faceColor,
      baseColor: baseColor,
      borderColor: borderColor,
      borderWidth: borderWidth,
      baseBorderColor: baseBorderColor ?? borderColor,
      baseDarken: baseDarken ?? ExerciseThemeTokens.keycapBaseDarken,
      borderRadius: ExerciseThemeTokens.radiusMd,
      child: child,
    );
  }
}

/// A mic button with keycap press feel for speaking exercises.
class PressableMicButton extends StatelessWidget {
  final bool isRecording;
  final VoidCallback? onTap;
  final bool enabled;
  final double height;
  final double borderRadius;
  final bool fullWidth;
  final double iconSize;
  final IconData idleIcon;
  final IconData recordingIcon;

  const PressableMicButton({
    super.key,
    required this.isRecording,
    this.onTap,
    this.enabled = true,
    this.height = 56,
    this.borderRadius = ExerciseThemeTokens.buttonRadius,
    this.fullWidth = true,
    this.iconSize = 34,
    this.idleIcon = Icons.mic_rounded,
    this.recordingIcon = Icons.stop_rounded,
  });

  @override
  Widget build(BuildContext context) {
    final activeFace = isRecording
        ? ExerciseThemeTokens.error
        : ExerciseThemeTokens.accent;
    final activeBase = isRecording
        ? ExerciseThemeTokens.error.withValues(alpha: 0.84)
        : ExerciseThemeTokens.accentHover;
    final faceColor = enabled ? activeFace : ExerciseThemeTokens.surfaceMuted;
    final baseColor = enabled ? activeBase : ExerciseThemeTokens.surfaceMuted;
    final borderColor = enabled ? activeBase : ExerciseThemeTokens.border;

    return SizedBox(
      width: fullWidth ? double.infinity : height,
      child: PressableKeycap(
        height: height,
        depth: ExerciseThemeTokens.keycapDepth,
        onTap: onTap,
        enabled: enabled,
        faceColor: faceColor,
        baseColor: baseColor,
        borderColor: borderColor,
        baseBorderColor: borderColor,
        borderRadius: borderRadius,
        shape: fullWidth ? BoxShape.rectangle : BoxShape.circle,
        child: Icon(
          isRecording ? recordingIcon : idleIcon,
          color: ExerciseThemeTokens.onAccent,
          size: iconSize,
        ),
      ),
    );
  }
}
