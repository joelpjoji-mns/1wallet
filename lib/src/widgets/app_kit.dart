import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:cupertino_native/cupertino_native.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../design/tokens.dart';

/// A consistent, accessible top-right action for single-screen form saves.
class HeaderSaveAction extends StatefulWidget {
  const HeaderSaveAction({
    required this.onPressed,
    super.key,
    this.isSaving = false,
  });

  final Future<void> Function() onPressed;
  final bool isSaving;

  @override
  State<HeaderSaveAction> createState() => _HeaderSaveActionState();
}

class _HeaderSaveActionState extends State<HeaderSaveAction> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) => HeaderIconButton(
    icon: Icons.check_rounded,
    loading: widget.isSaving || _busy,
    onPressed: widget.isSaving || _busy
        ? null
        : () async {
            setState(() => _busy = true);
            try {
              await widget.onPressed();
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          },
    semanticLabel: widget.isSaving || _busy ? 'Saving' : 'Save',
  );
}

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
            EdgeInsets.only(
              bottom:
                  AppSizes.bottomBarClearance +
                  MediaQuery.paddingOf(context).bottom +
                  AppSizes.bottomBarGap,
            ),
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
              bottom: isDesktop
                  ? AppSpacing.xl
                  : AppSizes.bottomBar +
                        AppSizes.bottomBarOuterVerticalPadding +
                        MediaQuery.paddingOf(context).bottom +
                        AppSizes.bottomBarGap,
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
      settings: LiquidGlassSettings(
        blur: Theme.of(context).brightness == Brightness.dark ? 16 : 12,
        thickness: Theme.of(context).brightness == Brightness.dark ? 22 : 18,
        glassColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xD9000000)
            : const Color(0x26FFFFFF),
        whitenStrength: 0,
        lightIntensity: Theme.of(context).brightness == Brightness.dark
            ? 0.12
            : 0.5,
        ambientStrength: Theme.of(context).brightness == Brightness.dark
            ? 0.04
            : 0.1,
        edgeAbsorption: Theme.of(context).brightness == Brightness.dark
            ? 0.22
            : 0,
      ),
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

/// Combines a base accessibility label with a pending-badge count so screen
/// readers announce e.g. "Open menu, 3 pending" instead of leaving the badge
/// number as a disconnected, context-less text node.
String? _headerButtonSemanticLabel(String? label, int? badge) {
  final count = badge ?? 0;
  if (label == null) return null;
  if (count <= 0) return label;
  return '$label, $count pending';
}

class GlassHeaderButton extends StatelessWidget {
  const GlassHeaderButton({
    required this.icon,
    required this.onPressed,
    this.badge,
    this.semanticLabel,
    super.key,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final int? badge;

  /// Accessibility label announced by screen readers (e.g. "Open menu").
  /// Without this, `GlassIconButton` exposes an empty label and the button
  /// is announced with no description of its action.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => HeaderIconButton(
    icon: icon,
    onPressed: onPressed,
    badge: badge,
    semanticLabel: semanticLabel,
  );
}

class AppMenuAction extends StatelessWidget {
  const AppMenuAction({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GlassHeaderButton(
      icon: Icons.menu_rounded,
      onPressed: onPressed,
      semanticLabel: 'Open menu',
    );
  }
}

class HeaderIconButton extends StatelessWidget {
  const HeaderIconButton({
    required this.icon,
    required this.onPressed,
    super.key,
    this.badge,
    this.semanticLabel,
    this.loading = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final int? badge;
  final bool loading;

  /// Accessibility label announced by screen readers. Without this,
  /// `GlassIconButton` exposes an empty label and the button is announced
  /// with no description of its action.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final badgeCount = badge ?? 0;
    final isApple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    final symbol = _sfSymbolFor(icon);
    if (isApple && symbol != null) {
      return Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Semantics(
          button: true,
          label: _headerButtonSemanticLabel(semanticLabel, badgeCount),
          child: CupertinoTheme(
            data: CupertinoThemeData(
              brightness: Theme.of(context).brightness,
              primaryColor: Theme.of(context).colorScheme.primary,
            ),
            child: CNButton.icon(
              icon: CNSymbol(symbol, size: 22),
              size: 44,
              enabled: onPressed != null,
              onPressed: onPressed,
              tint: Theme.of(context).colorScheme.primary,
              style: CNButtonStyle.glass,
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(left: 6.0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          UnconstrainedBox(
            child: GlassIconButton(
              icon: loading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon),
              iconSize: 22,
              size: 44,
              quality: GlassQuality.standard,
              onPressed: onPressed,
              semanticLabel: _headerButtonSemanticLabel(
                semanticLabel,
                badgeCount,
              ),
            ),
          ),
          if (badgeCount > 0)
            Positioned(
              right: 8,
              top: 8,
              // Badge count is folded into the semanticLabel above; exclude
              // this visual duplicate so screen readers don't announce it
              // twice, disconnected from context.
              child: ExcludeSemantics(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    badgeCount > 9 ? '9+' : '$badgeCount',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onError,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String? _sfSymbolFor(IconData icon) => switch (icon) {
  Icons.menu_rounded || Icons.menu => 'line.3.horizontal',
  Icons.arrow_back_rounded || Icons.arrow_back => 'chevron.left',
  Icons.add_rounded || Icons.add => 'plus',
  Icons.check_rounded || Icons.check => 'checkmark',
  Icons.close_rounded || Icons.close => 'xmark',
  Icons.search_rounded || Icons.search => 'magnifyingglass',
  Icons.refresh_rounded || Icons.refresh => 'arrow.clockwise',
  Icons.more_horiz_rounded || Icons.more_horiz => 'ellipsis',
  Icons.edit_rounded || Icons.edit => 'pencil',
  Icons.delete_outline_rounded || Icons.delete_outline => 'trash',
  Icons.notifications_outlined || Icons.notifications => 'bell',
  _ => null,
};

/// Shared action control. Apple builds use the package's native button;
/// Android and other platforms use the package's shader-backed glass button.
class AppActionButton extends StatelessWidget {
  const AppActionButton({
    required this.label,
    required this.onPressed,
    super.key,
    this.icon,
    this.enabled = true,
    this.prominent = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool enabled;
  final bool prominent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isApple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (isApple) {
      return Semantics(
        button: true,
        label: label,
        child: CupertinoTheme(
          data: CupertinoThemeData(
            brightness: Theme.of(context).brightness,
            primaryColor: scheme.primary,
          ),
          child: CNButton(
            label: label,
            enabled: enabled && onPressed != null,
            onPressed: onPressed,
            height: compact ? 34 : 48,
            tint: scheme.primary,
            style: prominent
                ? CNButtonStyle.prominentGlass
                : CNButtonStyle.glass,
          ),
        ),
      );
    }

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 18,
            color: prominent ? scheme.onPrimary : scheme.primary,
          ),
          const SizedBox(width: AppSpacing.xs),
        ],
        Text(
          label,
          style: TextStyle(
            color: prominent ? scheme.onPrimary : scheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
    return GlassButton.custom(
      label: label,
      onTap: onPressed ?? () {},
      enabled: enabled && onPressed != null,
      height: compact ? 36 : 48,
      shape: LiquidRoundedRectangle(borderRadius: AppRadii.pill),
      useOwnLayer: true,
      quality: GlassQuality.standard,
      style: prominent ? GlassButtonStyle.prominent : GlassButtonStyle.filled,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 18),
        child: content,
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
    this.glass = true,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;
  final Widget child;

  /// Uses the package's refractive glass surface when true. Set false when
  /// this section is already placed on another glass surface.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final content = Material(
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
                  AppActionButton(
                    label: actionLabel!,
                    onPressed: onAction,
                    compact: true,
                  ),
              ],
            ),
            SizedBox(height: compact ? AppSpacing.sm : AppSpacing.md),
            child,
          ],
        ),
      ),
    );

    if (glass) {
      return GlassCard(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        shape: LiquidRoundedSuperellipse(borderRadius: AppRadii.md),
        quality: GlassQuality.standard,
        child: content,
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: scheme.outlineVariant.withAlpha(140)),
      ),
      child: content,
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
    this.glass = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final MetricTone tone;
  final bool compact;
  final VoidCallback? onTap;

  /// Opts this tile into a refractive `GlassCard` surface instead of the
  /// default opaque background.
  ///
  /// `MetricTile` is almost always used two-to-four at a time inside a
  /// `SectionCard`'s summary row — defaulting to glass here meant nesting
  /// one refractive `GlassCard` inside another, which the package
  /// explicitly calls an anti-pattern (double-refraction, wasted fill-rate).
  /// Defaults to `false`; only flip it on for a standalone tile that isn't
  /// nested in another glass surface.
  final bool glass;

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

    final content = Material(
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
    );

    if (glass) {
      return GlassCard(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        shape: LiquidRoundedSuperellipse(borderRadius: AppRadii.md),
        quality: GlassQuality.standard,
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: scheme.outlineVariant.withAlpha(140)),
      ),
      child: content,
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

/// Material-compatible input API backed by the package's glass text field.
/// This lets existing form flows migrate without changing validation or
/// controllers while keeping input surfaces consistent across routes.
class AppGlassTextField extends StatelessWidget {
  const AppGlassTextField({
    super.key,
    this.controller,
    this.focusNode,
    this.decoration = const InputDecoration(),
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.minLines,
    this.maxLines = 1,
    this.maxLength,
    this.obscureText = false,
    this.enabled = true,
    this.readOnly = false,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.textAlign = TextAlign.start,
    this.style,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final InputDecoration decoration;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final int? minLines;
  final int maxLines;
  final int? maxLength;
  final bool obscureText;
  final bool enabled;
  final bool readOnly;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final TextAlign textAlign;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final decorationEnabled = decoration.enabled;
    final effectiveEnabled = enabled && decorationEnabled;
    Widget? suffix = decoration.suffixIcon;
    if (suffix == null && decoration.suffixText != null) {
      suffix = Padding(
        padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
        child: Center(widthFactor: 1, child: Text(decoration.suffixText!)),
      );
    }

    return GlassTextField(
      controller: controller,
      focusNode: focusNode,
      placeholder: decoration.hintText ?? decoration.labelText,
      prefixIcon: decoration.prefixIcon,
      suffixIcon: suffix,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      inputFormatters: inputFormatters,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      obscureText: obscureText,
      enabled: effectiveEnabled,
      readOnly: readOnly,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textStyle:
          style ?? TextStyle(color: Theme.of(context).colorScheme.onSurface),
      quality: GlassQuality.standard,
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
    this.glass = false,
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

  /// Opts this row into a refractive `GlassCard` surface instead of the
  /// default opaque background.
  ///
  /// `PremiumRow` is the app's general-purpose row for scrolling
  /// lists/pickers (accounts, categories, currencies, transactions, ...),
  /// often rendering dozens of instances at once. Per the
  /// `liquid_glass_widgets` package guidance, liquid glass is reserved for
  /// navigation/control chrome — dense list rows and scrolling content
  /// should stay opaque, so this defaults to `false`. Only flip it on for a
  /// genuinely standalone/highlighted row rendered a handful of times, not
  /// for list items rendered in bulk.
  final bool glass;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final content = Material(
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
                                color: scheme.onSurfaceVariant.withAlphaFactor(
                                  0.8,
                                ),
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
    );

    if (glass) {
      return GlassCard(
        margin: EdgeInsets.zero,
        padding: EdgeInsets.zero,
        shape: LiquidRoundedSuperellipse(borderRadius: AppRadii.md),
        // GlassQuality.standard is the package's own recommended tier for
        // scrollable list rows (lightweight shader, 5-10x faster than
        // BackdropFilter, "works correctly during scrolling"). Reserve
        // `premium` for static, non-scrolling hero surfaces instead.
        quality: GlassQuality.standard,
        clipBehavior: Clip.antiAlias,
        child: content,
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: scheme.outlineVariant.withAlpha(140)),
      ),
      child: content,
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
    this.secondary,
    this.contentPadding,
  });

  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData? icon;
  final Widget? secondary;
  final EdgeInsetsGeometry? contentPadding;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
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
              if (secondary != null) ...[
                secondary!,
                const SizedBox(width: AppSpacing.sm),
              ],
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
              // ExcludeFocus keeps the switch from claiming its own
              // independent keyboard-focus stop. Without it, the switch's
              // own focusability blocks MergeSemantics from absorbing its
              // toggled/enabled flags into the single merged node below,
              // leaving screen readers without the on/off state — matching
              // the workaround Flutter's own SwitchListTile applies.
              //
              // Prefer the CupertinoNative platform switch on Apple devices
              // and Liquid Glass's switch on Android and other platforms.
              ExcludeFocus(
                child: IgnorePointer(
                  ignoring: !enabled,
                  child: Opacity(
                    opacity: enabled ? 1 : 0.38,
                    child:
                        defaultTargetPlatform == TargetPlatform.iOS ||
                            defaultTargetPlatform == TargetPlatform.macOS
                        ? CupertinoTheme(
                            data: CupertinoThemeData(
                              brightness: Theme.of(context).brightness,
                              primaryColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                            ),
                            child: CNSwitch(
                              value: value,
                              enabled: enabled,
                              onChanged: onChanged ?? (_) {},
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          )
                        : GlassSwitch(
                            value: value,
                            onChanged: onChanged ?? (_) {},
                            activeColor: Theme.of(context).colorScheme.primary,
                            useOwnLayer: true,
                            quality: GlassQuality.standard,
                            semanticLabel: '',
                          ),
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
            AppActionButton(
              label: actionLabel!,
              onPressed: onAction,
              icon: Icons.add_rounded,
              prominent: true,
            ),
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
      semanticLabel: 'Back',
    );
  }
}
