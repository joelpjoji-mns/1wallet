import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';

class DrawerMetricCard extends StatelessWidget {
  const DrawerMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surface.withAlpha(190),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: scheme.outlineVariant.withAlpha(180)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withAlpha(28),
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w900,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class DrawerInfoChip extends StatelessWidget {
  const DrawerInfoChip({
    required this.icon,
    required this.label,
    required this.color,
    super.key,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(18),
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withAlpha(55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class DrawerSection extends StatelessWidget {
  const DrawerSection({
    required this.title,
    required this.rows,
    required this.selectedIndex,
    required this.onTabSelected,
    required this.icon,
    required this.surfaceTint,
    super.key,
    this.titleColor,
  });

  final String title;
  final List<DrawerRowConfig> rows;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final IconData icon;
  final Color surfaceTint;
  final Color? titleColor;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              4,
              AppSpacing.md,
              2,
            ),
            child: Text(
              title.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color:
                    (titleColor ??
                            Theme.of(context).colorScheme.onSurfaceVariant)
                        .withAlphaFactor(0.8),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: surfaceTint.withAlpha(12),
              borderRadius: BorderRadius.circular(AppRadii.xl),
              border: Border.all(color: scheme.outlineVariant.withAlpha(160)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: surfaceTint.withAlpha(22),
                        borderRadius: BorderRadius.circular(AppRadii.md),
                      ),
                      child: Icon(
                        icon,
                        size: 16,
                        color: titleColor ?? surfaceTint,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        'Quick access',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                for (var index = 0; index < rows.length; index++) ...[
                  DrawerRouteTile(
                    config: rows[index],
                    selectedIndex: selectedIndex,
                    onTabSelected: onTabSelected,
                    accentColor: titleColor ?? surfaceTint,
                  ),
                  if (index != rows.length - 1)
                    const SizedBox(height: AppSpacing.xs),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DrawerRouteTile extends StatefulWidget {
  const DrawerRouteTile({
    required this.config,
    required this.selectedIndex,
    required this.onTabSelected,
    super.key,
    this.danger = false,
    this.onTapOverride,
    this.accentColor,
  });

  final DrawerRowConfig config;
  final int selectedIndex;
  final ValueChanged<int> onTabSelected;
  final bool danger;
  final VoidCallback? onTapOverride;
  final Color? accentColor;

  @override
  State<DrawerRouteTile> createState() => _DrawerRouteTileState();
}

class _DrawerRouteTileState extends State<DrawerRouteTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active =
        widget.config.tabIndex != null &&
        widget.config.tabIndex == widget.selectedIndex;
    final accentColor = widget.accentColor ?? scheme.primary;
    final iconFg = widget.danger
        ? scheme.error
        : active
        ? accentColor
        : scheme.onSurfaceVariant;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: active
            ? accentColor.withAlpha(18)
            : _hovered
            ? scheme.surfaceContainerHighest.withAlpha(170)
            : scheme.surface.withAlpha(140),
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(
          color: active
              ? accentColor.withAlpha(110)
              : scheme.outlineVariant.withAlpha(120),
        ),
        boxShadow: active
            ? [
                BoxShadow(
                  color: accentColor.withAlpha(26),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.lg),
          onHover: (h) => setState(() => _hovered = h),
          onTap:
              widget.onTapOverride ??
              () {
                if (widget.config.tabIndex != null) {
                  widget.onTabSelected(widget.config.tabIndex!);
                } else if (widget.config.route != null) {
                  final router = GoRouter.of(context);
                  Navigator.of(context).pop();
                  router.push(widget.config.route!);
                }
              },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 11,
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: widget.danger
                        ? scheme.error.withAlpha(20)
                        : active
                        ? accentColor.withAlpha(20)
                        : scheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                  child: Icon(widget.config.icon, size: 18, color: iconFg),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    widget.config.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: active ? accentColor : scheme.onSurface,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.config.badge != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: widget.danger
                          ? scheme.errorContainer
                          : scheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      widget.config.badge!,
                      style: TextStyle(
                        color: widget.danger
                            ? scheme.onErrorContainer
                            : scheme.onSecondaryContainer,
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: active ? accentColor : scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DrawerRowConfig {
  const DrawerRowConfig._({
    required this.label,
    required this.icon,
    this.route,
    this.tabIndex,
    this.badge,
  });

  factory DrawerRowConfig.route(
    String label,
    IconData icon,
    String route, {
    String? badge,
  }) {
    return DrawerRowConfig._(
      label: label,
      icon: icon,
      route: route,
      badge: badge,
    );
  }

  factory DrawerRowConfig.tab(String label, IconData icon, int tabIndex) {
    return DrawerRowConfig._(label: label, icon: icon, tabIndex: tabIndex);
  }

  final String label;
  final IconData icon;
  final String? route;
  final int? tabIndex;
  final String? badge;
}
