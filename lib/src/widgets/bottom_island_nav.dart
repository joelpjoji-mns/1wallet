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
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
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
                        glowColor: scheme.primary.withAlphaFactor(0.3),
                      ),
                  ],
                  selectedIndex: selectedIndex,
                  onTabSelected: (index) =>
                      onSelected(items[index].pageIndex ?? index),
                  barHeight: 72,
                  horizontalPadding: 14,
                  verticalPadding: 12,
                  spacing: 6,
                  showIndicator: true,
                  // Explicit indicator color that reads well in both themes
                  indicatorColor: scheme.primary.withAlphaFactor(
                    isDark ? 0.30 : 0.14,
                  ),
                  selectedIconColor: scheme.primary,
                  unselectedIconColor: scheme.onSurfaceVariant,
                  selectedLabelColor: scheme.primary,
                  unselectedLabelColor: scheme.onSurfaceVariant,
                  quality: GlassQuality.premium,
                  backgroundQuality: GlassQuality.standard,
                  // Explicit glass settings to prevent AMOLED white bleed:
                  // on pure-black AMOLED surfaces the shader can refract
                  // against almost nothing and appear white — higher thickness
                  // + more blur keeps the glass effect dark and visible.
                  settings: LiquidGlassSettings(
                    blur: isDark ? 26 : 16,
                    thickness: isDark ? 52 : 26,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
