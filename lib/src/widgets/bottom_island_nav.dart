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
    this.trailingAction,
    super.key,
  });

  final List<IslandTabItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSizes.bottomBarOuterVerticalPadding,
          AppSpacing.md,
          AppSizes.bottomBarOuterVerticalPadding,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final hasAction = trailingAction != null;
            final maxWidth =
                AppSizes.islandMaxWidth + (hasAction ? 72 + AppSpacing.sm : 0);
            final width = constraints.maxWidth < maxWidth
                ? constraints.maxWidth
                : maxWidth;
            return Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: width,
                child: Row(
                  children: [
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeOutCubic,
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
                          horizontalPadding: 14,
                          verticalPadding: 12,
                          spacing: 6,
                          showIndicator: true,
                          quality: GlassQuality.standard,
                          // Explicit indicator color that reads well in both themes
                          indicatorColor: scheme.primary.withAlphaFactor(
                            isDark ? 0.30 : 0.14,
                          ),
                          selectedIconColor: scheme.primary,
                          unselectedIconColor: scheme.onSurfaceVariant,
                          selectedLabelColor: scheme.primary,
                          unselectedLabelColor: scheme.onSurfaceVariant,

                          backgroundQuality: GlassQuality.standard,
                          // Explicit glass settings to prevent AMOLED white bleed:
                          // on pure-black AMOLED surfaces the shader can refract
                          // against almost nothing and appear white — higher thickness
                          // + more blur keeps the glass effect dark and visible.
                          settings: LiquidGlassSettings(
                            blur: isDark ? 26 : 16,
                            thickness: isDark ? 30 : 26,
                            glassColor: isDark
                                ? const Color(0xD9000000)
                                : const Color(0x26FFFFFF),
                            whitenStrength: isDark ? 0 : 0.08,
                            lightIntensity: isDark ? 0.12 : 0.5,
                            ambientStrength: isDark ? 0.04 : 0.1,
                            edgeAbsorption: isDark ? 0.22 : 0,
                          ),
                        ),
                      ),
                    ),
                    if (trailingAction != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 240),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: trailingAction!,
                      ),
                    ],
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
