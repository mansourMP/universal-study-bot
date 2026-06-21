import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dragon_chinese/design_system/colors.dart';
import 'package:dragon_chinese/design_system/typography.dart';
import 'package:dragon_chinese/design_system/pressable_keycap.dart';
import 'package:dragon_chinese/design_system/exercise_theme.dart';

/// Universal Game Button
/// High-quality interactive button for all languages.
/// Features: 3D depth, squish animation, haptic feedback.
enum GameButtonVariant {
  primary,    // Main CTA (Theme color)
  secondary,  // Secondary action
  outline,    // Bordered neutral
  ghost,      // Transparent
  correct,    // Success state
  wrong,      // Error state
  locked,     // Disabled/Locked
}

class GameButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final GameButtonVariant variant;
  final bool isLoading;
  final IconData? icon;
  final bool fullWidth;
  final Color? customColor; // Override for specific language themes

  const GameButton({
    super.key,
    required this.text,
    this.onPressed,
    this.variant = GameButtonVariant.primary,
    this.isLoading = false,
    this.icon,
    this.fullWidth = false,
    this.customColor,
  });

  @override
  State<GameButton> createState() => _GameButtonState();
}

class _GameButtonState extends State<GameButton> {
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _handleTapDown(_) {
    if (widget.onPressed == null) return;
    setState(() => _isPressed = true);
    HapticFeedback.lightImpact();
  }

  void _handleTapUp(_) {
    if (widget.onPressed == null) return;
    setState(() => _isPressed = false);
  }

  void _handleTapCancel() {
    setState(() => _isPressed = false);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.variant == GameButtonVariant.locked) {
      return _buildContent(locked: true);
    }

    return GestureDetector(
      onTapDown: _handleTapDown,
      onTapUp: _handleTapUp,
      onTapCancel: _handleTapCancel,
      onTap: widget.onPressed == null ? null : () {
        HapticFeedback.mediumImpact();
        widget.onPressed?.call();
      },
      child: _buildContent(),
    );
  }

  Widget _buildContent({bool locked = false}) {
    final colors = _getColors(locked);
    
    final borderColor = colors.borderColor ?? Colors.transparent;
    final label = Text(
      widget.text.toUpperCase(),
      style: DragonTypography.buttonMedium.copyWith(
        color: colors.text,
        letterSpacing: 1.0,
      ),
    );

    return SizedBox(
      width: widget.fullWidth ? double.infinity : null,
      height: 52,
      child: PressableKeycap(
        height: 52,
        depth: ExerciseThemeTokens.keycapDepth,
        onTap: widget.onPressed,
        enabled: !locked && widget.onPressed != null,
        faceColor: colors.background,
        baseColor: colors.background,
        baseDarken: ExerciseThemeTokens.keycapBaseDarken,
        borderColor: borderColor,
        baseBorderColor: Colors.transparent,
        borderRadius: 16,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, color: colors.text, size: 20),
              const SizedBox(width: 8),
            ],
            label,
          ],
        ),
      ),
    );
  }

  _ButtonColors _getColors(bool locked) {
    if (locked) {
      return _ButtonColors(
        background: AppColors.surfaceAlt,
        text: AppColors.textTertiary,
        borderColor: AppColors.textTertiary.withOpacity(0.2),
      );
    }

    switch (widget.variant) {
      case GameButtonVariant.primary:
        final base = widget.customColor ?? AppColors.brandPrimary;
        return _ButtonColors(
          background: base,
          text: Colors.white,
        );
      case GameButtonVariant.secondary:
         return _ButtonColors(
          background: AppColors.surface,
          text: AppColors.brandPrimary,
          borderColor: AppColors.surfaceAlt,
        );
      case GameButtonVariant.outline:
        return _ButtonColors(
          background: Colors.transparent,
          text: AppColors.textSecondary,
          borderColor: AppColors.textSecondary.withOpacity(0.5),
        );
      case GameButtonVariant.ghost:
        return _ButtonColors(
          background: Colors.transparent,
          text: AppColors.brandPrimary,
        );
      case GameButtonVariant.correct:
        return _ButtonColors(
          background: AppColors.success,
          text: Colors.white,
        );
      case GameButtonVariant.wrong:
        return _ButtonColors(
          background: AppColors.error,
          text: Colors.white,
        );
      default:
        return _ButtonColors(
          background: AppColors.brandPrimary,
          text: Colors.white,
        );
    }
  }
}

class _ButtonColors {
  final Color background;
  final Color text;
  final Color? borderColor;

  _ButtonColors({
    required this.background,
    required this.text,
    this.borderColor,
  });
}
