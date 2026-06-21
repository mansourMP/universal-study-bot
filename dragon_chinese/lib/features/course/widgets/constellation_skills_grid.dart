import 'package:flutter/material.dart';
import 'package:dragon_chinese/design_system/design_system.dart';

class ConstellationSkill {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final double progress;
  final VoidCallback onTap;

  const ConstellationSkill({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.progress,
    required this.onTap,
  });
}

class ConstellationSkillsGrid extends StatelessWidget {
  final List<ConstellationSkill> skills;

  const ConstellationSkillsGrid({super.key, required this.skills});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final breakpoint = DsBreakpoints.of(context);
        final columns = switch (breakpoint) {
          DsBreakpoint.compact => 2,
          DsBreakpoint.medium => 3,
          DsBreakpoint.expanded => 4,
        };
        const spacing = DsSpacing.md;
        final contentWidth = constraints.maxWidth - (spacing * (columns - 1));
        final tileWidth = contentWidth / columns;
        final tileHeight = (tileWidth * 0.84).clamp(160.0, 198.0);

        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(0, DsSpacing.sm, 0, DsSpacing.xl),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            mainAxisExtent: tileHeight,
          ),
          itemCount: skills.length,
          itemBuilder: (context, index) {
            final skill = skills[index];
            return _ConstellationSkillCard(skill: skill, index: index);
          },
        );
      },
    );
  }
}

class _ConstellationSkillCard extends StatelessWidget {
  final ConstellationSkill skill;
  final int index;

  const _ConstellationSkillCard({required this.skill, required this.index});

  @override
  Widget build(BuildContext context) {
    final progress = skill.progress.clamp(0.0, 1.0);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: skill.onTap,
        child: Ink(
          padding: const EdgeInsets.all(DsSpacing.md),
          decoration: BoxDecoration(
            color: DsColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: DsColors.borderSubtle),
            boxShadow: const [
              BoxShadow(
                color: Color(0x08000000),
                blurRadius: 8,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: skill.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(skill.icon, color: skill.color, size: 18),
              ),
              const SizedBox(height: DsSpacing.md),
              Text(
                skill.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DsTypography.title.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                skill.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: DsTypography.caption.copyWith(
                  color: DsColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              ClipRRect(
                borderRadius: BorderRadius.circular(DsRadii.sm),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: DsColors.surfaceAlt,
                  valueColor: AlwaysStoppedAnimation(skill.color),
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${(progress * 100).round()}%',
                style: DsTypography.caption.copyWith(
                  color: DsColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
