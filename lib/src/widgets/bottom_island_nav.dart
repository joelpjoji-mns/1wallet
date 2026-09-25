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
    super.key,
  });

  final List<IslandTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth < AppSizes.islandMaxWidth
                ? constraints.maxWidth
                : AppSizes.islandMaxWidth;
            return Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: width,
                child: GlassTabBar.bottom(
                  tabs: [
                    for (final item in items)
                      GlassTab(
                        label: item.title,
                        semanticLabel: item.title,
                        icon: Icon(item.icon),
                        activeIcon: Icon(item.activeIcon),
                        glowColor: scheme.primary.withAlphaFactor(0.2),
                      ),
                  ],
                  selectedIndex: selectedIndex,
                  onTabSelected: (index) =>
                      onSelected(items[index].pageIndex ?? index),
                  barHeight: 64,
                  horizontalPadding: 12,
                  verticalPadding: 8,
                  spacing: 4,
                  showIndicator: true,
                  indicatorColor: scheme.primary.withAlphaFactor(
                    isDark ? 0.24 : 0.15,
                  ),
                  selectedIconColor: scheme.primary,
                  unselectedIconColor: scheme.onSurfaceVariant,
                  selectedLabelColor: scheme.primary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  quality: GlassQuality.premium,
                  backgroundQuality: GlassQuality.standard,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
