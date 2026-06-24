import 'dart:ui';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design/tokens.dart';
import '../../startup/startup_state.dart';

abstract final class LaunchPalette {
  static const background = Color(0xFF0F1820);
  static const backgroundDeep = Color(0xFF0B1218);
  static const primary = Color(0xFFA9C7FF);
  static const tertiary = Color(0xFF9BDDB5);
  static const gold = Color(0xFFDFC894);
  static const text = Color(0xFFF4F7FB);
  static const mutedText = Color(0xFFC8D3DF);
}

class _ResolvedLaunchPalette {
  const _ResolvedLaunchPalette({
    required this.background,
    required this.backgroundDeep,
    required this.primary,
    required this.tertiary,
    required this.gold,
    required this.text,
    required this.mutedText,
    required this.rail,
    required this.railActive,
    required this.completedRail,
    required this.line,
    required this.bandPrimary,
    required this.bandTertiary,
    required this.bandGold,
    required this.cardFill,
    required this.focusBorder,
    required this.focusFill,
    required this.haloFill,
    required this.markBackground,
    required this.markBorder,
    required this.markGlint,
    required this.progressTrack,
    required this.stageBorder,
  });

  final Color background;
  final Color backgroundDeep;
  final Color primary;
  final Color tertiary;
  final Color gold;
  final Color text;
  final Color mutedText;
  final Color rail;
  final Color railActive;
  final Color completedRail;
  final Color line;
  final Color bandPrimary;
  final Color bandTertiary;
  final Color bandGold;
  final Color cardFill;
  final Color focusBorder;
  final Color focusFill;
  final Color haloFill;
  final Color markBackground;
  final Color markBorder;
  final Color markGlint;
  final Color progressTrack;
  final Color stageBorder;
}

_ResolvedLaunchPalette _resolveLaunchPalette(BuildContext context) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final isDark = theme.brightness == Brightness.dark;
  final isAmoled = isDark && _isTrueBlackColor(scheme.surface);
  final background = isAmoled
      ? Colors.black
      : isDark
      ? scheme.surface
      : scheme.surface;
  final backgroundDeep = isAmoled
      ? Colors.black
      : isDark
      ? const Color(0xFF07090C)
      : scheme.surfaceContainerLowest;
  final surfaceRaised = isAmoled
      ? const Color(0xFF0B0B0B)
      : isDark
      ? scheme.surfaceContainer
      : scheme.surfaceContainerLow;
  final neutralBandAlpha = isAmoled
      ? 0.026
      : isDark
      ? 0.052
      : 0.038;
  final neutralPlateAlpha = isAmoled
      ? 0.038
      : isDark
      ? 0.07
      : 0.05;
  final accentAlpha = isAmoled
      ? 0.11
      : isDark
      ? 0.15
      : 0.11;

  return _ResolvedLaunchPalette(
    background: background,
    backgroundDeep: backgroundDeep,
    primary: scheme.primary,
    tertiary: scheme.tertiary,
    gold: scheme.secondary,
    text: scheme.onSurface,
    mutedText: scheme.onSurfaceVariant,
    rail: scheme.onSurface.withAlphaFactor(isDark ? 0.11 : 0.07),
    railActive: scheme.primary.withAlphaFactor(accentAlpha),
    completedRail: scheme.onSurface.withAlphaFactor(isDark ? 0.14 : 0.09),
    line: scheme.onSurface.withAlphaFactor(isDark ? 0.12 : 0.08),
    bandPrimary: scheme.onSurface.withAlphaFactor(neutralBandAlpha),
    bandTertiary: scheme.onSurface.withAlphaFactor(neutralBandAlpha),
    bandGold: scheme.onSurface.withAlphaFactor(neutralBandAlpha * 0.72),
    cardFill: scheme.surface,
    focusBorder: scheme.outline.withAlphaFactor(isDark ? 0.26 : 0.2),
    focusFill: scheme.onSurface.withAlphaFactor(neutralPlateAlpha),
    haloFill: scheme.primary.withAlphaFactor(isDark ? 0.064 : 0.052),
    markBackground: surfaceRaised.withAlphaFactor(0.98),
    markBorder: scheme.outline.withAlphaFactor(isDark ? 0.32 : 0.28),
    markGlint: scheme.onSurface.withAlphaFactor(isDark ? 0.11 : 0.08),
    progressTrack: scheme.onSurface.withAlphaFactor(isDark ? 0.12 : 0.08),
    stageBorder: scheme.outline.withAlphaFactor(0.22),
  );
}

bool _isTrueBlackColor(Color color) =>
    color.toARGB32() == Colors.black.toARGB32();

class LaunchBackdrop extends StatefulWidget {
  const LaunchBackdrop({super.key, this.child});

  final Widget? child;

  @override
  State<LaunchBackdrop> createState() => _LaunchBackdropState();
}

class _LaunchBackdropState extends State<LaunchBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF000000) : const Color(0xFFF0F4F8);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final xOffset1 = 50 * math.sin(t * math.pi * 2);
        final yOffset1 = 50 * math.cos(t * math.pi * 2);

        final xOffset2 = -40 * math.cos(t * math.pi * 2);
        final yOffset2 = 60 * math.sin(t * math.pi * 2);

        return Container(
          color: bg,
          child: Stack(
            children: [
              Positioned(
                top: -100 + yOffset1,
                left: -100 + xOffset1,
                child: Container(
                  width: 400,
                  height: 400,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.primary.withValues(
                      alpha: isDark ? 0.4 : 0.6,
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: -50 + yOffset2,
                right: -50 + xOffset2,
                child: Container(
                  width: 350,
                  height: 350,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.tertiary.withValues(
                      alpha: isDark ? 0.3 : 0.5,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
                  child: Container(color: Colors.transparent),
                ),
              ),
              if (widget.child != null) widget.child!,
            ],
          ),
        );
      },
    );
  }
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.borderRadius,
  });
  final Widget child;
  final EdgeInsets padding;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = borderRadius ?? 24.0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.white.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.white.withValues(alpha: 0.5),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class StaggeredFadeIn extends StatefulWidget {
  const StaggeredFadeIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
  });
  final Widget child;
  final Duration delay;

  @override
  State<StaggeredFadeIn> createState() => _StaggeredFadeInState();
}

class _StaggeredFadeInState extends State<StaggeredFadeIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

class LaunchBrandMark extends StatefulWidget {
  const LaunchBrandMark({super.key, this.size = 112, this.animated = true});

  final double size;
  final bool animated;

  @override
  State<LaunchBrandMark> createState() => _LaunchBrandMarkState();
}

class _LaunchBrandMarkState extends State<LaunchBrandMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    if (widget.animated) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = _resolveLaunchPalette(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        final pulse = widget.animated
            ? 1 + (math.sin(t * math.pi) * 0.04)
            : 1.0;
        final glintX = -widget.size + (widget.size * 2 * t);
        return SizedBox(
          width: widget.size * 1.7,
          height: widget.size * 1.5,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Transform.scale(
                scale: pulse,
                child: Container(
                  width: widget.size * 1.36,
                  height: widget.size * 1.05,
                  decoration: BoxDecoration(
                    color: palette.haloFill,
                    borderRadius: BorderRadius.circular(widget.size * 0.38),
                    border: Border.all(
                      color: palette.primary.withAlphaFactor(0.36),
                      width: 2,
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: pulse,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.size * 0.31),
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: palette.markBackground,
                      borderRadius: BorderRadius.circular(widget.size * 0.31),
                      border: Border.all(color: palette.markBorder),
                      boxShadow: [
                        BoxShadow(
                          color: palette.primary.withAlphaFactor(0.18),
                          blurRadius: 32,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(glintX, 0),
                          child: Transform.rotate(
                            angle: -22 * math.pi / 180,
                            child: Container(
                              width: widget.size * 0.4,
                              height: widget.size * 1.45,
                              color: palette.markGlint,
                            ),
                          ),
                        ),
                        Transform.rotate(
                          angle: -8 * math.pi / 180,
                          child: Container(
                            width: widget.size * 0.68,
                            height: widget.size * 0.48,
                            decoration: BoxDecoration(
                              color: palette.cardFill,
                              borderRadius: BorderRadius.circular(
                                widget.size * 0.15,
                              ),
                              border: Border.all(
                                color: palette.primary,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                        Transform.translate(
                          offset: Offset(0, 1.5 - (3 * t)),
                          child: Icon(
                            Icons.account_balance_wallet_outlined,
                            size: widget.size * 0.39,
                            color: palette.primary,
                          ),
                        ),
                        Positioned(
                          right: widget.size * 0.09,
                          bottom: widget.size * 0.09,
                          child: CircleAvatar(
                            radius: widget.size * 0.16,
                            backgroundColor: palette.tertiary,
                            child: Text(
                              '1',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onTertiary,
                                fontSize: widget.size * 0.16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class AnimatedBrandScene extends StatelessWidget {
  const AnimatedBrandScene({
    super.key,
    this.message = 'Your money, organized beautifully',
    this.compact = false,
  });

  final String message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = _resolveLaunchPalette(context);
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      tween: Tween(begin: 0, end: 1),
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - value)),
            child: child,
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LaunchBrandMark(size: compact ? 96 : 122),
          SizedBox(height: compact ? AppSpacing.lg : AppSpacing.xl),
          Text(
            '1wallet',
            style: TextStyle(
              color: palette.text,
              fontSize: 34,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.mutedText,
              fontSize: 16,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class BrandedLoadingState extends StatelessWidget {
  const BrandedLoadingState({
    required this.stage,
    required this.message,
    this.progress,
    super.key,
  });

  final StartupStage stage;
  final String message;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LaunchBackdrop(
        child: SafeArea(
          child: Center(
            child: StaggeredFadeIn(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.1),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.wallet_rounded,
                        size: 40,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: Text(
                      message,
                      key: ValueKey(message),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (progress != null) ...[
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 200,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.1),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressTrack extends StatefulWidget {
  const _ProgressTrack({required this.palette});

  final _ResolvedLaunchPalette palette;

  @override
  State<_ProgressTrack> createState() => _ProgressTrackState();
}

class _ProgressTrackState extends State<_ProgressTrack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        return ClipRRect(
          borderRadius: BorderRadius.circular(AppRadii.pill),
          child: Container(
            width: 156,
            height: 5,
            color: widget.palette.progressTrack,
            child: Align(
              alignment: Alignment(-1.5 + (3.0 * value), 0),
              child: FractionallySizedBox(
                widthFactor: 0.46 + (0.34 * math.sin(value * math.pi)),
                child: Container(color: widget.palette.primary),
              ),
            ),
          ),
        );
      },
    );
  }
}

class RecoveryState extends StatelessWidget {
  const RecoveryState({
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    super.key,
    this.secondaryLabel,
    this.onSecondaryAction,
    this.tertiaryLabel,
    this.onTertiaryAction,
  });

  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondaryAction;
  final String? tertiaryLabel;
  final VoidCallback? onTertiaryAction;

  @override
  Widget build(BuildContext context) {
    final palette = _resolveLaunchPalette(context);
    return Scaffold(
      body: LaunchBackdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const LaunchBrandMark(size: 96, animated: false),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.text,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.7,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: palette.mutedText,
                    fontSize: 16,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: palette.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                  child: Text(actionLabel),
                ),
                if (secondaryLabel != null && onSecondaryAction != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: onSecondaryAction,
                    child: Text(
                      secondaryLabel!,
                      style: TextStyle(color: palette.mutedText),
                    ),
                  ),
                ],
                if (tertiaryLabel != null && onTertiaryAction != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: onTertiaryAction,
                    child: Text(
                      tertiaryLabel!,
                      style: TextStyle(
                        color: palette.mutedText.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
