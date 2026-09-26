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
  });

  final String title;
  final IconData icon;
  final IconData activeIcon;
  final int? pageIndex;
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

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Keep full natural island width without excessive empty gaps on sides
            final islandWidth = (constraints.maxWidth - 28)
                .clamp(320.0, AppSizes.islandMaxWidth)
                .toDouble();
            final totalWidth = constraints.maxWidth;

            return Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: totalWidth,
                height: 148,
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.bottomCenter,
                  children: [
                    // Animate island bar position: shifts to right slightly when FAB compacts down, or stays centered
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeInOutCubicEmphasized,
                      left: compactAction
                          ? ((totalWidth - islandWidth) / 2) + 24
                          : (totalWidth - islandWidth) / 2,
                      bottom: 0,
                      width: islandWidth,
                      child: GlassTabBar.bottom(
                        tabs: [
                          for (final item in items)
                            GlassTab(
                              label: item.title,
                              semanticLabel: item.title,
                              icon: Icon(item.icon),
                              activeIcon: Icon(item.activeIcon),
                            ),
                        ],
                        selectedIndex: selectedIndex,
                        onTabSelected: (index) =>
                            onSelected(items[index].pageIndex ?? index),
                        barHeight: AppSizes.bottomBarContentHeight,
                        horizontalPadding: 10,
                        verticalPadding: 12,
                        spacing: 6,
                        showIndicator: true,
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
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 380),
                        curve: Curves.easeInOutCubicEmphasized,
                        right: 14,
                        bottom: compactAction
                            ? 0
                            : AppSizes.bottomBarContentHeight + 16,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 250),
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
