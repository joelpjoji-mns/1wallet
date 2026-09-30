import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../design/tokens.dart';

@immutable
class IslandTabItem {
  const IslandTabItem({
    required this.title,
    required this.icon,
    required this.activeIcon,
    this.pageIndex,
    this.badgeCount,
  });

  final String title;
  final IconData icon;
  final IconData activeIcon;
  final int? pageIndex;
  final int? badgeCount;
}

class BottomIslandNavBar extends StatelessWidget {
  const BottomIslandNavBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.action,
    this.compactAction = false,
    super.key,
  });

  final List<IslandTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget? action;
  final bool compactAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassTheme = GlassThemeData.of(context);
    final glassSettings = glassTheme.settingsFor(context)?.applyTo(
          const LiquidGlassSettings(),
        );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: AppSizes.bottomBarOuterVerticalPadding,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final totalWidth = constraints.maxWidth;
            final hasDownFab = compactAction && action != null;
            // When FAB is down beside the island bar, shrink the island and shift left
            // leaving room for 64px FAB + 12px margin on the right.
            final islandWidth = hasDownFab
                ? (totalWidth - 76).clamp(240.0, AppSizes.islandMaxWidth - 76).toDouble()
                : totalWidth.clamp(320.0, AppSizes.islandMaxWidth).toDouble();

            final islandLeft = hasDownFab
                ? 0.0
                : (totalWidth - islandWidth) / 2;

            return Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: totalWidth,
                height: 148,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Island bar position: shifts left and shrinks to fit FAB on right when down, or centered
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOutCubic,
                      left: islandLeft,
                      bottom: 0,
                      width: islandWidth,
                      child: GlassTabBar.bottom(
                        tabs: [
                          for (final item in items)
                            GlassTab(
                              label: item.title,
                              semanticLabel: item.title,
                              icon: item.badgeCount != null && item.badgeCount! > 0
                                  ? Badge.count(
                                      count: item.badgeCount!,
                                      backgroundColor: scheme.error,
                                      child: Icon(item.icon),
                                    )
                                  : Icon(item.icon),
                              activeIcon:
                                  item.badgeCount != null && item.badgeCount! > 0
                                      ? Badge.count(
                                          count: item.badgeCount!,
                                          backgroundColor: scheme.error,
                                          child: Icon(item.activeIcon),
                                        )
                                      : Icon(item.activeIcon),
                            ),
                        ],
                        selectedIndex: selectedIndex,
                        onTabSelected: (index) =>
                            onSelected(items[index].pageIndex ?? index),
                        barHeight: AppSizes.bottomBarContentHeight,
                        horizontalPadding: hasDownFab ? 6 : 10,
                        verticalPadding: 12,
                        spacing: hasDownFab ? 4 : 6,
                        showIndicator: true,
                        settings: glassSettings,
                        quality: GlassQuality.standard,
                        indicatorColor: scheme.primary.withAlphaFactor(
                          isDark ? 0.30 : 0.14,
                        ),
                        selectedIconColor: scheme.primary,
                        unselectedIconColor: scheme.onSurfaceVariant,
                        selectedLabelColor: scheme.primary,
                        unselectedLabelColor: scheme.onSurfaceVariant,
                        backgroundQuality: GlassQuality.standard,
                      ),
                    ),
                    if (action != null)
                      // FAB moving down animation smoothly anchored to bottom right
                      // When compactAction is true, center the 64px FAB with the 96px total bar height ((96 - 64) / 2 = 16)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        right: 0,
                        bottom: compactAction
                            ? (AppSizes.bottomBar - 64) / 2
                            : AppSizes.bottomBarContentHeight + 16,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 180),
                          opacity: 1.0,
                          child: action!,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
