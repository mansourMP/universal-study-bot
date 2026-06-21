import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dragon_chinese/core/config/app_config.dart';
import 'package:dragon_chinese/design_system/design_system.dart';
import 'package:dragon_chinese/features/course/screens/dashboard_screen.dart';
import 'package:dragon_chinese/features/profile/screens/profile_screen.dart';
import 'package:dragon_chinese/features/tutor/screens/tutor_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell>
    with SingleTickerProviderStateMixin {
  static const double _kDrawerWidthFactor = 0.82;
  static const double _kDrawerEdgeDragWidth = 34;
  static const double _kBottomNavHeight = 62;
  int _selectedIndex = 0;
  bool _profileOpen = false;
  String _currentSourceLang = 'en';
  String _currentTargetLang = AppConfig.targetLang;
  late final AnimationController _drawerController;
  bool _allowDrawerDrag = false;
  double _drawerWidthPx = 0;
  bool _drawerOpenHapticFired = false;
  bool _drawerClosedHapticFired = true;

  final List<AppBottomNavTab> _tabs = const [
    AppBottomNavTab(
      label: 'Course',
      icon: Icons.map_outlined,
      activeIcon: Icons.map,
    ),
    AppBottomNavTab(
      label: 'AI',
      icon: Icons.auto_awesome_outlined,
      activeIcon: Icons.auto_awesome,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _drawerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    )..addListener(_handleDrawerHaptics);
  }

  @override
  void dispose() {
    _drawerController.removeListener(_handleDrawerHaptics);
    _drawerController.dispose();
    super.dispose();
  }

  bool get _isDrawerOpen => _drawerController.value > 0.01;

  void _handleDrawerHaptics() {
    final v = _drawerController.value;
    if (v >= 0.96 && !_drawerOpenHapticFired) {
      _drawerOpenHapticFired = true;
      _drawerClosedHapticFired = false;
      HapticFeedback.selectionClick();
    } else if (v <= 0.04 && !_drawerClosedHapticFired) {
      _drawerClosedHapticFired = true;
      _drawerOpenHapticFired = false;
      HapticFeedback.selectionClick();
    }
  }

  void _openDrawer() {
    if (_drawerController.value >= 0.99) return;
    HapticFeedback.lightImpact();
    _drawerController.animateTo(1, curve: Curves.easeOutQuart);
  }

  void _closeDrawer() {
    if (_drawerController.value <= 0.01) return;
    HapticFeedback.lightImpact();
    _drawerController.animateTo(0, curve: Curves.easeOutQuart);
  }

  void _toggleDrawer() {
    if (_isDrawerOpen) {
      _closeDrawer();
    } else {
      _openDrawer();
    }
  }

  void _onTabSelected(int index) {
    if (index == _selectedIndex && !_profileOpen) return;
    HapticFeedback.lightImpact();
    setState(() {
      _selectedIndex = index;
      _profileOpen = false;
    });
    if (_isDrawerOpen) {
      _closeDrawer();
    }
  }

  void _openProfileFromDrawer() {
    if (!_profileOpen) {
      HapticFeedback.lightImpact();
      setState(() {
        _profileOpen = true;
      });
    }
    _closeDrawer();
  }

  void _onLanguageChanged(String newLang) {
    setState(() {
      _currentSourceLang = newLang;
    });
  }

  void _onTargetLanguageChanged(String newLang) {
    setState(() {
      _currentTargetLang = newLang;
    });
  }

  void _onHorizontalDragStart(DragStartDetails details, double drawerWidth) {
    final startedFromEdge = details.globalPosition.dx <= _kDrawerEdgeDragWidth;
    _allowDrawerDrag = _isDrawerOpen || startedFromEdge;
    _drawerWidthPx = drawerWidth;
    if (_allowDrawerDrag) {
      HapticFeedback.selectionClick();
    }
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_allowDrawerDrag || _drawerWidthPx <= 0) return;
    _drawerController.value =
        (_drawerController.value + (details.primaryDelta ?? 0) / _drawerWidthPx)
            .clamp(0.0, 1.0);
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_allowDrawerDrag) return;
    _allowDrawerDrag = false;
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (velocity > 220) {
      _openDrawer();
      return;
    }
    if (velocity < -220) {
      _closeDrawer();
      return;
    }
    if (_drawerController.value >= 0.5) {
      _openDrawer();
    } else {
      _closeDrawer();
    }
  }

  Widget _buildDrawerContent(BuildContext context, double drawerWidth) {
    final textTheme = Theme.of(context).textTheme;
    return SizedBox(
      width: drawerWidth,
      child: Container(
        color: const Color(0xFFF4F5F7),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Omnis',
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  width: 34,
                  height: 2,
                  decoration: BoxDecoration(
                    color: AppColors.textPrimary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 20),
                _DrawerNavItem(
                  label: 'Profile',
                  icon: Icons.person_outline,
                  selected: _profileOpen,
                  onTap: _openProfileFromDrawer,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mainScreens = [
      DashboardScreen(
        currentSourceLang: _currentSourceLang,
        currentTargetLang: _currentTargetLang,
        onLanguageChanged: _onLanguageChanged,
        onTargetLanguageChanged: _onTargetLanguageChanged,
        onMenuTap: _toggleDrawer,
      ),
      const TutorScreen(),
    ];
    final content = _profileOpen
        ? const ProfileScreen()
        : IndexedStack(index: _selectedIndex, children: mainScreens);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= AppBreakpoints.tablet;
        final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
        final drawerWidth = constraints.maxWidth * _kDrawerWidthFactor;

        if (isWide) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: Row(
              children: [
                SafeArea(
                  child: NavigationRail(
                    selectedIndex: _selectedIndex,
                    onDestinationSelected: _onTabSelected,
                    labelType: NavigationRailLabelType.all,
                    destinations: _tabs
                        .map(
                          (tab) => NavigationRailDestination(
                            icon: Icon(tab.icon),
                            selectedIcon: Icon(tab.activeIcon),
                            label: Text(tab.label),
                          ),
                        )
                        .toList(),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  color: Theme.of(
                    context,
                  ).colorScheme.outline.withValues(alpha: 0.2),
                ),
                Expanded(child: content),
              ],
            ),
          );
        }

        final panel = Scaffold(
          backgroundColor: AppColors.background,
          body: content,
          bottomNavigationBar: keyboardOpen
              ? null
              : AppBottomNav(
                  height: _kBottomNavHeight,
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: _onTabSelected,
                  tabs: _tabs,
                ),
        );

        return AnimatedBuilder(
          animation: _drawerController,
          builder: (context, child) {
            final t = Curves.easeOutCubic.transform(_drawerController.value);
            final drawerSlideX = -drawerWidth * (1 - t);
            final contentScale = 1 - (0.02 * t);
            final contentShift = drawerWidth * 0.06 * t;

            return Scaffold(
              backgroundColor: AppColors.background,
              body: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: (d) =>
                    _onHorizontalDragStart(d, drawerWidth),
                onHorizontalDragUpdate: _onHorizontalDragUpdate,
                onHorizontalDragEnd: _onHorizontalDragEnd,
                child: Stack(
                  children: [
                    Transform.translate(
                      offset: Offset(contentShift, 0),
                      child: Transform.scale(
                        alignment: Alignment.centerLeft,
                        scale: contentScale,
                        child: panel,
                      ),
                    ),
                    if (t > 0)
                      Positioned.fill(
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: _closeDrawer,
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.12 * t),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: drawerSlideX,
                      width: drawerWidth,
                      child: IgnorePointer(
                        ignoring: t <= 0,
                        child: Stack(
                          children: [
                            _buildDrawerContent(context, drawerWidth),
                            Positioned(
                              top: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                width: 1,
                                color: Colors.black.withValues(alpha: 0.10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DrawerNavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _DrawerNavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.textPrimary : AppColors.textSecondary;
    final bg = selected
        ? Colors.white.withValues(alpha: 0.72)
        : Colors.transparent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? Colors.black.withValues(alpha: 0.08)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 20, color: fg),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
