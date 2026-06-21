import 'package:flutter/material.dart';

class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.tabs,
    this.height = 62,
    this.indicatorColor,
    this.backgroundColor,
    this.selectedColor,
    this.unselectedColor,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AppBottomNavTab> tabs;
  final double height;
  final Color? indicatorColor;
  final Color? backgroundColor;
  final Color? selectedColor;
  final Color? unselectedColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bgColor = backgroundColor ?? cs.surface;
    final selColor = selectedColor ?? cs.onSecondaryContainer;
    final unselColor = unselectedColor ?? cs.onSurfaceVariant;
    final indColor = indicatorColor ?? cs.secondaryContainer;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Container(
      height: height + bottomInset,
      color: bgColor,
      child: Column(
        children: [
          Divider(
            height: 1,
            thickness: 0.5,
            color: cs.outline.withValues(alpha: 0.2),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Row(
                children: List.generate(tabs.length, (i) {
                  return Expanded(
                    child: _NavItem(
                      tab: tabs[i],
                      selected: i == selectedIndex,
                      indicatorColor: indColor,
                      selectedColor: selColor,
                      unselectedColor: unselColor,
                      onTap: () => onDestinationSelected(i),
                    ),
                  );
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppBottomNavTab {
  const AppBottomNavTab({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.indicatorColor,
    required this.selectedColor,
    required this.unselectedColor,
    required this.onTap,
  });

  final AppBottomNavTab tab;
  final bool selected;
  final Color indicatorColor;
  final Color selectedColor;
  final Color unselectedColor;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.selected ? 1.0 : 0.0,
    );
    _progress = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
  }

  @override
  void didUpdateWidget(covariant _NavItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      if (widget.selected) {
        _ctrl.forward();
      } else {
        _ctrl.reverse();
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _progress,
        builder: (context, _) {
          final t = _progress.value;
          final color = Color.lerp(
            widget.unselectedColor,
            widget.selectedColor,
            t,
          )!;

          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    width: t > 0.01 ? 64 : 0,
                    height: 32,
                    decoration: BoxDecoration(
                      color: widget.indicatorColor.withValues(alpha: t),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Opacity(
                          opacity: 1 - t,
                          child: Icon(widget.tab.icon, size: 22, color: color),
                        ),
                        Opacity(
                          opacity: t,
                          child: Icon(
                            widget.tab.activeIcon,
                            size: 22,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                widget.tab.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: t > 0.5 ? FontWeight.w600 : FontWeight.w400,
                  color: color,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
