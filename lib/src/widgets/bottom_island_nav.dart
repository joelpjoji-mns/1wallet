import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

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
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 390;
            final islandWidth = math.min(constraints.maxWidth, 430.0);
            final navHeight = compact ? 72.0 : 76.0;
            const navPadding = 6.0;
            final indicatorHeight = navHeight - navPadding * 2;
            final tabWidth = (islandWidth - navPadding * 2) / items.length;
            final currentItemIndex = items.indexWhere(
              (item) => (item.pageIndex ?? items.indexOf(item)) == selectedIndex,
            );
            final selectedItemIndex = currentItemIndex < 0 ? 0 : currentItemIndex;

            // Proportions exactly matching the reference image
            final pillWidth = compact ? 76.0 : 80.0;
            final tabCenter = navPadding + tabWidth * (selectedItemIndex + 0.5);
            final left = tabCenter - pillWidth / 2;

            return Align(
              alignment: Alignment.bottomCenter,
              child: _GlassIsland(
                width: islandWidth,
                height: navHeight,
                child: Stack(
                  children: [
                    // Animated selection pill
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutExpo,
                      left: left,
                      top: navPadding,
                      width: pillWidth,
                      height: indicatorHeight,
                      child: const _SelectedIslandBubble(),
                    ),
                    // Tab buttons
                    Align(
                      alignment: Alignment.center,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6.0),
                        child: Row(
                          children: [
                            for (var index = 0; index < items.length; index++)
                              Expanded(
                                child: _IslandButton(
                                  item: items[index],
                                  selected:
                                      (items[index].pageIndex ?? index) ==
                                      selectedIndex,
                                  compact: compact,
                                  onTap: () => onSelected(
                                    items[index].pageIndex ?? index,
                                  ),
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
        ),
      ),
    );
  }
}

class _GlassIsland extends StatelessWidget {
  const _GlassIsland({
    required this.width,
    required this.height,
    required this.child,
  });

  final double width;
  final double height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Glass surface: we want it to stand out against the white/dark background
    final glassFill = isDark
        ? scheme.surfaceContainerHighest.withAlpha(200)
        : scheme.surfaceContainerHigh.withAlpha(220);

    // Border highlight (top shimmer)
    final borderColor = isDark
        ? Colors.white.withAlphaFactor(0.14)
        : Colors.white.withAlphaFactor(0.9);

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: glassFill,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: borderColor, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlphaFactor(isDark ? 0.42 : 0.08),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Inner gradient shimmer overlay
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withAlphaFactor(isDark ? 0.08 : 0.38),
                        scheme.primary.withAlphaFactor(isDark ? 0.04 : 0.02),
                        Colors.white.withAlphaFactor(isDark ? 0.04 : 0.12),
                      ],
                    ),
                  ),
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedIslandBubble extends StatelessWidget {
  const _SelectedIslandBubble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        color: scheme.primary.withAlphaFactor(isDark ? 0.25 : 0.15),
      ),
    );
  }
}

class _IslandButton extends StatefulWidget {
  const _IslandButton({
    required this.item,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final IslandTabItem item;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  State<_IslandButton> createState() => _IslandButtonState();
}

class _IslandButtonState extends State<_IslandButton>
    with SingleTickerProviderStateMixin {

  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _onTapDown(_) {
    _scaleCtrl.forward();
  }

  void _onTapUp(_) {
    _scaleCtrl.reverse();
  }

  void _onTapCancel() {
    _scaleCtrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final activeColor = scheme.primary;
    final inactiveColor = isDark
        ? scheme.onSurface.withAlphaFactor(0.55)
        : scheme.onSurface.withAlphaFactor(0.45);
    final color = widget.selected ? activeColor : inactiveColor;

    final iconSize = widget.selected
        ? (widget.compact ? 24.0 : 26.0)
        : (widget.compact ? 22.0 : 24.0);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: _onTapDown,
      onTapCancel: _onTapCancel,
      onTapUp: _onTapUp,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 200),
          scale: widget.selected ? 1.04 : 1.0,
          curve: Curves.easeOutCubic,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                duration: const Duration(milliseconds: 200),
                scale: widget.selected ? 1.08 : 1.0,
                curve: Curves.easeOutBack,
                child: Icon(
                  widget.selected
                      ? widget.item.activeIcon
                      : widget.item.icon,
                  size: iconSize,
                  color: color,
                ),
              ),
              Padding(
                padding: EdgeInsets.only(top: widget.compact ? 2 : 3),
                child: Text(
                  widget.item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: widget.compact ? 10.5 : 11.5,
                    height: 1.0,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
