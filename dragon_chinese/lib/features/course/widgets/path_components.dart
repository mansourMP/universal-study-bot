import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/path_theme.dart';
import 'package:dragon_chinese/features/course/adapters/path_view_models.dart';

class SyncBanner extends StatelessWidget {
  final VoidCallback onRetry;
  const SyncBanner({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: PathThemeTokens.highlight.withOpacity(0.25),
        borderRadius: BorderRadius.circular(PathThemeTokens.cardRadius),
        border: Border.all(color: PathThemeTokens.highlight),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded,
              color: PathThemeTokens.accentGold),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Can’t sync right now",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  "Can’t sync right now. Pull to refresh or try again.",
                  style: TextStyle(
                    color: PathThemeTokens.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text("Retry"),
          ),
        ],
      ),
    );
  }
}

class MissionChip extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const MissionChip({super.key, required this.label, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PathThemeTokens.pillRadius),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: PathThemeTokens.surface,
          borderRadius: BorderRadius.circular(PathThemeTokens.pillRadius),
          border: Border.all(color: PathThemeTokens.borderSubtle),
          boxShadow: [PathThemeTokens.shadowSm],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.flag_rounded,
                size: 16, color: PathThemeTokens.brandAccent),
            const SizedBox(width: 6),
            Text(
              label,
              style: PathThemeTokens.subtitle.copyWith(
                fontWeight: FontWeight.w600,
                color: PathThemeTokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReadinessCard extends StatelessWidget {
  final int score;
  final String label;
  final VoidCallback onTap;

  const ReadinessCard({
    super.key,
    required this.score,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(PathThemeTokens.cardRadius),
      child: Ink(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: PathThemeTokens.surface,
          borderRadius: BorderRadius.circular(PathThemeTokens.cardRadius),
          border: Border.all(color: PathThemeTokens.borderSubtle),
          boxShadow: [PathThemeTokens.shadowMd],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: PathThemeTokens.brandAccentSoft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  '$score',
                  style: PathThemeTokens.title.copyWith(
                    fontWeight: FontWeight.w700,
                    color: PathThemeTokens.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'HSK1 readiness',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PathThemeTokens.sectionLabel,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PathThemeTokens.subtitle,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded,
                color: PathThemeTokens.textSecondary),
          ],
        ),
      ),
    );
  }
}

class UnitHeaderCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final int completed;
  final int total;
  final bool isCurrent;
  final String? focusLabel;

  const UnitHeaderCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.completed,
    required this.total,
    required this.isCurrent,
    required this.focusLabel,
  });

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : completed / total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PathThemeTokens.surface,
        borderRadius: BorderRadius.circular(PathThemeTokens.cardRadius),
        border: Border.all(color: PathThemeTokens.border),
        boxShadow: [PathThemeTokens.shadowMd],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: PathThemeTokens.title),
                    const SizedBox(height: 4),
                    Text(subtitle, style: PathThemeTokens.subtitle),
                  ],
                ),
              ),
              if (focusLabel != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: PathThemeTokens.brandAccentSoft,
                    borderRadius:
                        BorderRadius.circular(PathThemeTokens.pillRadius),
                  ),
                  child: Text(
                    focusLabel!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: PathThemeTokens.textPrimary,
                    ),
                  ),
                ),
              if (isCurrent) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: PathThemeTokens.accentMuted,
                    borderRadius: BorderRadius.circular(PathThemeTokens.pillRadius),
                  ),
                  child: const Text(
                    "Current unit",
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: PathThemeTokens.surfaceMuted,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      progress >= 1 ? PathThemeTokens.success : PathThemeTokens.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                "$completed/$total",
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class SkillChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool showLabel;

  const SkillChip({
    super.key,
    required this.label,
    required this.icon,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: showLabel ? 10 : 8, vertical: 6),
      decoration: BoxDecoration(
        color: PathThemeTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(PathThemeTokens.pillRadius),
        border: Border.all(color: PathThemeTokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: PathThemeTokens.inkMuted),
          if (showLabel) ...[
            const SizedBox(width: 6),
            Text(label, style: PathThemeTokens.chipText),
          ],
        ],
      ),
    );
  }
}

class LessonCard extends StatelessWidget {
  final String title;
  final String promise;
  final String timeLabel;
  final IconData icon;
  final bool isLocked;
  final bool isCompleted;
  final bool isCurrent;
  final List<SkillChip> chips;
  final double progress;
  final String? statusLabel;
  final String? imageUrl;
  final bool hasAudio;
  final VoidCallback? onTap;

  const LessonCard({
    super.key,
    required this.title,
    required this.promise,
    required this.timeLabel,
    required this.icon,
    required this.isLocked,
    required this.isCompleted,
    required this.isCurrent,
    required this.chips,
    required this.progress,
    required this.statusLabel,
    required this.imageUrl,
    required this.hasAudio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isNext = statusLabel == 'Next';
    final baseColor =
        isLocked ? PathThemeTokens.surfaceMuted : PathThemeTokens.surface;
    final borderColor =
        (isCurrent || isNext)
            ? PathThemeTokens.brandAccent
            : PathThemeTokens.borderSubtle;
    final contentColor =
        isLocked ? PathThemeTokens.textSecondary : PathThemeTokens.textPrimary;
    final defaultBorder = BorderSide(color: borderColor, width: 0.8);
    final leftBorder = (isCurrent || isNext)
        ? BorderSide(color: PathThemeTokens.brandAccent, width: 4)
        : defaultBorder;

    return Opacity(
      opacity: isLocked ? 0.85 : 1,
      child: _PressScale(
        enabled: !(isLocked || isCompleted),
        child: InkWell(
          onTap: (isLocked || isCompleted) ? null : onTap,
          borderRadius: BorderRadius.circular(PathThemeTokens.cardRadius),
          child: Ink(
            padding: EdgeInsets.fromLTRB(
              PathThemeTokens.cardPaddingX,
              PathThemeTokens.cardPaddingY,
              PathThemeTokens.cardPaddingX,
              PathThemeTokens.cardBottomPadding,
            ),
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(PathThemeTokens.cardRadius),
              border: Border(
                left: leftBorder,
                top: defaultBorder,
                right: defaultBorder,
                bottom: defaultBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Thumbnail(
                      icon: icon,
                      imageUrl: imageUrl,
                      muted: isLocked,
                      highlight: isCurrent || isNext,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: PathThemeTokens.sectionLabel.copyWith(
                              color: contentColor,
                              fontSize: 17,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              ...chips,
                              const SizedBox(width: 8),
                              if (timeLabel.isNotEmpty)
                                Text(
                                  timeLabel,
                                  style: PathThemeTokens.subtitle.copyWith(fontSize: 12),
                                ),
                              const Spacer(),
                              _buildStatusPill(statusLabel),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (progress > 0 && progress < 1)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: PathThemeTokens.surfaceMuted,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          PathThemeTokens.brandAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(String? statusLabel) {
    // Only show pill for Active/Next states. Hide for Completed/Locked to reduce noise.
    final String? label = (isCurrent || statusLabel == 'Next') 
        ? (statusLabel ?? 'Start') 
        : null;

    if (label == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: PathThemeTokens.brandAccent,
        borderRadius: BorderRadius.circular(PathThemeTokens.pillRadius),
      ),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontWeight: FontWeight.w800, 
          color: Colors.white, 
          fontSize: 10,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _PressScale extends StatefulWidget {
  final Widget child;
  final bool enabled;
  const _PressScale({required this.child, required this.enabled});

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.enabled
          ? (_) => setState(() => _scale = 0.98)
          : null,
      onTapUp: widget.enabled ? (_) => setState(() => _scale = 1) : null,
      onTapCancel: widget.enabled ? () => setState(() => _scale = 1) : null,
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  final IconData icon;
  final String? imageUrl;
  final bool muted;
  final bool highlight;
  const _Thumbnail({
    required this.icon,
    required this.imageUrl,
    required this.muted,
    required this.highlight,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: PathThemeTokens.thumbSize,
      height: PathThemeTokens.thumbSize,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: imageUrl == null ? PathThemeTokens.surfaceMuted : Colors.transparent,
        gradient: imageUrl == null
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  PathThemeTokens.headerTint,
                  PathThemeTokens.surfaceMuted,
                ],
              )
            : null,
        border: Border.all(
          color: highlight ? PathThemeTokens.brandAccent : PathThemeTokens.border,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: imageUrl == null
            ? Icon(
                icon,
                size: 20,
                color: muted ? PathThemeTokens.textSecondary : PathThemeTokens.textPrimary,
              )
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Icon(
                  icon,
                  size: 20,
                  color: PathThemeTokens.textSecondary,
                ),
              ),
      ),
    );
  }
}

class PathSkeleton extends StatelessWidget {
  final int units;
  final int lessonsPerUnit;
  const PathSkeleton({super.key, this.units = 2, this.lessonsPerUnit = 3});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: units,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _block(width: 140, height: 14),
              const SizedBox(height: 12),
              _block(width: double.infinity, height: 84, radius: 16),
              const SizedBox(height: 12),
              ...List.generate(
                lessonsPerUnit,
                (_) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _block(width: double.infinity, height: 72, radius: 16),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _block({
    required double width,
    required double height,
    double radius = 8,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: PathThemeTokens.surfaceMuted,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class EmptyPathState extends StatelessWidget {
  final VoidCallback onRetry;
  const EmptyPathState({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: PathThemeTokens.surfaceMuted,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(Icons.map_outlined, size: 48),
            ),
            const SizedBox(height: 16),
            Text(
              'No lessons yet',
              style: PathThemeTokens.title,
            ),
            const SizedBox(height: 6),
            Text(
              'We’ll be ready soon. Tap reload to try again.',
              style: PathThemeTokens.subtitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Reload'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailsRow extends StatelessWidget {
  final List<SkillChip> chips;
  final bool hasAudio;
  final String timeLabel;

  const _DetailsRow({
    required this.chips,
    required this.hasAudio,
    required this.timeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final hasDetails =
        chips.isNotEmpty || hasAudio || timeLabel.isNotEmpty;
    if (!hasDetails) return const SizedBox.shrink();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...chips,
              if (hasAudio)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.volume_up_rounded,
                        size: 16, color: PathThemeTokens.textSecondary),
                    const SizedBox(width: 4),
                    Text('Audio', style: PathThemeTokens.subtitle),
                  ],
                ),
            ],
          ),
        ),
        if (timeLabel.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(timeLabel, style: PathThemeTokens.subtitle),
          ),
      ],
    );
  }
}

class ProgressRailNode extends StatelessWidget {
  final LessonState state;
  final bool isFirst;
  final bool isLast;

  const ProgressRailNode({
    super.key,
    required this.state,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    final Color lineColor = PathThemeTokens.borderSubtle;
    final double nodeCenter =
        PathThemeTokens.railTopOffset + PathThemeTokens.railNodeSize / 2;
    final bool isCurrent = state == LessonState.current;
    final bool isCompleted = state == LessonState.completed;
    final Color nodeFill = isCompleted
        ? PathThemeTokens.brandAccent
        : isCurrent
            ? PathThemeTokens.surface
            : PathThemeTokens.surface;
    final Color nodeStroke = isCompleted
        ? PathThemeTokens.brandAccent
        : isCurrent
            ? PathThemeTokens.brandAccent
            : PathThemeTokens.textSecondary;

    return SizedBox(
      width: 26,
      child: Column(
        children: [
          if (!isFirst)
            Container(
              height: nodeCenter,
              width: 2,
              color: lineColor,
            ),
          Container(
            width: PathThemeTokens.railNodeSize,
            height: PathThemeTokens.railNodeSize,
            decoration: BoxDecoration(
              color: nodeFill,
              shape: BoxShape.circle,
              border: Border.all(color: nodeStroke, width: 2),
              boxShadow: isCurrent
                  ? [
                      BoxShadow(
                        color: PathThemeTokens.brandAccentSoft.withOpacity(0.8),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              isCompleted
                  ? Icons.check
                  : (state == LessonState.locked
                      ? Icons.lock
                      : Icons.circle),
              size: 12,
              color: isCompleted
                  ? Colors.white
                  : (state == LessonState.locked
                      ? PathThemeTokens.textSecondary
                      : PathThemeTokens.brandAccent),
            ),
          ),
          if (!isLast)
            Container(
              height: PathThemeTokens.railSpacing - nodeCenter,
              width: 2,
              color: lineColor,
            ),
        ],
      ),
    );
  }
}
