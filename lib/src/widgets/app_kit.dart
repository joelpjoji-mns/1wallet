import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../design/tokens.dart';

class AppResponsiveLayout extends StatelessWidget {
  const AppResponsiveLayout({
    required this.mobile,
    required this.desktop,
    this.desktopBreakpoint = 800,
    super.key,
  });

  final Widget mobile;
  final Widget desktop;
  final double desktopBreakpoint;

  static bool isDesktop(BuildContext context, {double breakpoint = 800}) {
    return MediaQuery.sizeOf(context).width >= breakpoint;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= desktopBreakpoint) {
          return desktop;
        }
        return mobile;
      },
    );
  }
}

class AppScreen extends StatelessWidget {
  const AppScreen({
    required this.title,
    required this.child,
    super.key,
    this.onMenuPressed,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.md,
      AppSpacing.xs,
      AppSpacing.md,
      AppSpacing.md,
    ),
    this.scrollable = true,
    this.floatingActionButton,
    this.maxWidth = 800,
  });

  final String title;
  final Widget child;
  final VoidCallback? onMenuPressed;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;
  final bool scrollable;
  final Widget? floatingActionButton;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final isDesktop = AppResponsiveLayout.isDesktop(context);

    // Adjust bottom clearance to account for bottom navigation bar on mobile
    final contentPadding = scrollable && !isDesktop
        ? padding.add(
            const EdgeInsets.only(bottom: AppSizes.bottomBarClearance),
          )
        : padding;

    Widget body = scrollable
        ? ListView(padding: contentPadding, children: [child])
        : Padding(padding: contentPadding, child: child);

    // Apply width constraint but preserve tight vertical constraints
    body = Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: body,
        ),
      ),
    );

    return ColoredBox(
      color: Colors.transparent,
      child: Stack(
        children: [
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: AppHeader(
                      title: title,
                      onMenuPressed: isDesktop
                          ? null
                          : onMenuPressed, // Hide menu button on desktop since drawer is persistent
                      actions: actions,
                    ),
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          ),
          if (floatingActionButton != null)
            Positioned(
              right: isDesktop ? AppSpacing.xl : AppSpacing.lg,
              bottom: isDesktop ? AppSpacing.xl : AppSizes.bottomBarClearance,
              child: floatingActionButton!,
            ),
        ],
      ),
    );
  }
}

class IslandFloatingActionButton extends StatelessWidget {
  const IslandFloatingActionButton({
    required this.icon,
    required this.onPressed,
    super.key,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    Widget button = GlassButton(
      icon: Icon(icon),
      label: tooltip ?? 'Action',
      onTap: onPressed,
      width: 64,
      height: 64,
      iconSize: 30,
      iconColor: Theme.of(context).colorScheme.primary,
      useOwnLayer: true,
      quality: GlassQuality.standard,
    );

    final tooltipMessage = tooltip;
    if (tooltipMessage != null && tooltipMessage.isNotEmpty) {
      button = Tooltip(message: tooltipMessage, child: button);
    }
    return button;
  }
}

class AppHeader extends StatelessWidget {
  const AppHeader({
    required this.title,
    super.key,
    this.onMenuPressed,
    this.actions = const [],
  });

  final String title;
  final VoidCallback? onMenuPressed;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return GlassIsolationScope(
      isolated: true,
      defaultQuality: GlassQuality.premium,
      child: GlassAppBar(
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        leading: onMenuPressed != null
            ? AppMenuAction(onPressed: onMenuPressed!)
            : canPop
            ? const AppBackAction()
            : null,
        actions: actions,
        centerTitle: false,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      ),
    );
  }
}

class GlassHeaderButton extends StatelessWidget {
  const GlassHeaderButton({
    required this.icon,
    required this.onPressed,
    this.badge,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget button = GlassIconButton(
      icon: Icon(icon),
      onPressed: onPressed,
      size: 48,
      iconSize: 24,
      quality: GlassQuality.standard,
    );

    if ((badge ?? 0) > 0) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.error,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Text(
                badge! > 9 ? '9+' : '$badge',
                style: TextStyle(
                  color: scheme.onError,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: button,
    );
  }
}

class AppMenuAction extends StatelessWidget {
  const AppMenuAction({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassHeaderButton(icon: Icons.menu_rounded, onPressed: onPressed);
  }
}

class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    required this.icon,
    required this.onPressed,
    super.key,
    this.badge,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6.0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GlassIconButton(
            icon: Icon(icon),
            iconSize: 26,
            size: 52,
            quality: GlassQuality.standard,
            onPressed: onPressed,
          ),
          if ((badge ?? 0) > 0)
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  badge! > 9 ? '9+' : '${badge!}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onError,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    required this.title,
    required this.child,
    super.key,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      shape: LiquidRoundedSuperellipse(borderRadius: AppRadii.md),
      quality: GlassQuality.standard,
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.all(compact ? AppSpacing.sm : AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        if (subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              subtitle!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (actionLabel != null && onAction != null)
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                      ),
                      onPressed: onAction,
                      child: Text(actionLabel!),
                    ),
                ],
              ),
              SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.label,
    required this.value,
    required this.icon,
    super.key,
    this.tone = MetricTone.standard,
    this.compact = false,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final MetricTone tone;
  final bool compact;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (tone) {
      MetricTone.positive =>
        Theme.of(context).brightness == Brightness.dark
            ? AppColors.positiveDark
            : AppColors.positiveLight,
      MetricTone.danger => scheme.error,
      MetricTone.warning => scheme.secondary,
      MetricTone.standard => scheme.primary,
    };
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      shape: LiquidRoundedSuperellipse(borderRadius: AppRadii.md),
      quality: GlassQuality.standard,
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? AppSpacing.sm : AppSpacing.md,
              vertical: compact ? AppSpacing.xs : AppSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                IconBubble(icon: icon, color: color, compact: true),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

enum MetricTone { standard, positive, danger, warning }

class IconBubble extends StatelessWidget {
  const IconBubble({
    required this.icon,
    super.key,
    this.color,
    this.compact = false,
  });

  final IconData icon;
  final Color? color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = color ?? scheme.primary;
    final size = compact ? 26.0 : 34.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: iconColor.withAlphaFactor(
          Theme.of(context).brightness == Brightness.dark ? 0.22 : 0.12,
        ),
        borderRadius: BorderRadius.circular(
          compact ? AppRadii.sm : AppRadii.md,
        ),
      ),
      child: Icon(icon, color: iconColor, size: compact ? 16 : 20),
    );
  }
}

class PremiumSearchInput extends StatefulWidget {
  const PremiumSearchInput({
    required this.hintText,
    required this.onChanged,
    super.key,
    this.value = '',
    this.height = 48,
  });

  final String hintText;
  final String value;
  final ValueChanged<String> onChanged;
  final double height;

  @override
  State<PremiumSearchInput> createState() => _PremiumSearchInputState();
}

class _PremiumSearchInputState extends State<PremiumSearchInput> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(PremiumSearchInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value && _controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassSearchBar(
      controller: _controller,
      placeholder: widget.hintText,
      onChanged: widget.onChanged,
      height: widget.height,
      textStyle: TextStyle(color: scheme.onSurface, fontSize: 16),
      searchIconColor: scheme.primary,
      quality: GlassQuality.standard,
      useOwnLayer: true,
    );
  }
}

class PremiumRow extends StatelessWidget {
  const PremiumRow({
    required this.icon,
    required this.title,
    required this.onTap,
    super.key,
    this.subtitle,
    this.meta,
    this.metaSubtitle,
    this.iconColor,
    this.selected = false,
    this.trailing,
    this.onLongPress,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? meta;
  final String? metaSubtitle;
  final Color? iconColor;
  final bool selected;
  final Widget? trailing;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return GlassCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      shape: LiquidRoundedSuperellipse(borderRadius: AppRadii.md),
      quality: GlassQuality.standard,
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.md),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.md,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconColor ?? scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: scheme.onSurface, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                          fontSize: 15,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (meta != null || metaSubtitle != null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: 2,
                          children: [
                            if (meta != null)
                              Text(
                                meta!,
                                style: TextStyle(
                                  color: selected
                                      ? scheme.primary
                                      : scheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            if (metaSubtitle != null)
                              Text(
                                metaSubtitle!,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant
                                      .withAlphaFactor(0.8),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ],
                      if (trailing != null) ...[
                        const SizedBox(width: AppSpacing.sm),
                        trailing!,
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                if (selected)
                  Icon(Icons.check_circle_rounded, color: scheme.primary)
                else
                  Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    required this.label,
    required this.value,
    super.key,
    this.icon,
    this.tone = MetricTone.standard,
  });

  final String label;
  final String value;
  final IconData? icon;
  final MetricTone tone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (tone) {
      MetricTone.positive =>
        Theme.of(context).brightness == Brightness.dark
            ? AppColors.positiveDark
            : AppColors.positiveLight,
      MetricTone.danger => scheme.error,
      MetricTone.warning => scheme.secondary,
      MetricTone.standard => scheme.onSurface,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            flex: 1,
            child: Text(
              label,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: color,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class AppSwitchListTile extends StatelessWidget {
  const AppSwitchListTile({
    required this.title,
    required this.value,
    required this.onChanged,
    super.key,
    this.subtitle,
    this.icon,
    this.contentPadding,
  });

  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    // MergeSemantics combines the title/subtitle text and the Switch's
    // "toggled" state into a single semantics node, matching the platform's
    // own SwitchListTile behavior. Without it, screen readers (TalkBack /
    // VoiceOver) expose the title, subtitle, and switch as separate,
    // disconnected stops instead of one coherent on/off control.
    return MergeSemantics(
      child: InkWell(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Padding(
          padding:
              contentPadding ??
              const EdgeInsets.symmetric(
                vertical: AppSpacing.sm,
                horizontal: AppSpacing.xs,
              ),
          child: Row(
            children: [
              if (icon != null) ...[
                IconBubble(icon: icon!, compact: true),
                const SizedBox(width: AppSpacing.md),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle(
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      child: title,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle(
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // ExcludeFocus keeps the Switch from claiming its own
              // independent keyboard-focus stop. Without it, the Switch's
              // own focusability blocks MergeSemantics from absorbing its
              // toggled/enabled flags into the single merged node below,
              // leaving screen readers without the on/off state — matching
              // the workaround Flutter's own SwitchListTile applies.
              ExcludeFocus(
                child: Switch.adaptive(
                  value: value,
                  onChanged: onChanged,
                  activeTrackColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconBubble(icon: icon, color: scheme.primary),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}

class Gap extends StatelessWidget {
  const Gap(this.size, {super.key});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(height: size, width: size);
}

class AppBackAction extends StatelessWidget {
  const AppBackAction({super.key});

  @override
  Widget build(BuildContext context) {
    return GlassHeaderButton(
      icon: Icons.arrow_back_rounded,
      onPressed: () => Navigator.of(context).maybePop(),
    );
  }
}
