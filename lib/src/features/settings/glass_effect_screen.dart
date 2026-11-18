import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart' as g1455;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';

/// Screen allowing the user to customize liquid optics separately for each
/// primary glass surface (Island Bar, Action Button (FAB), Dropdown & Menus,
/// Toolbars & Buttons, and General Cards) with interactive sliders, Clear vs Regular
/// finish presets, and an interactive real-time live preview.
class GlassEffectScreen extends ConsumerStatefulWidget {
  const GlassEffectScreen({super.key});

  @override
  ConsumerState<GlassEffectScreen> createState() => _GlassEffectScreenState();
}

class _GlassEffectScreenState extends ConsumerState<GlassEffectScreen> {
  Timer? _commitTimer;

  GlassComponentTarget _selectedTarget = GlassComponentTarget.islandBar;
  late double _blur;
  late double _backgroundOpacity;
  late double _refractionLevel;
  late double _specularOpacity;
  late AppGlassFinish _currentFinish;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    final prefs = ref.read(ledgerProvider).preferences;
    final optics = prefs.opticsFor(_selectedTarget);
    _currentFinish = optics.finish;
    _blur = optics.blur;
    _backgroundOpacity = optics.backgroundOpacity;
    _refractionLevel = optics.refractionLevel;
    _specularOpacity = optics.specularOpacity;
    _initialized = true;
  }

  @override
  void dispose() {
    _commitTimer?.cancel();
    super.dispose();
  }

  void _switchTarget(GlassComponentTarget target) {
    if (target == _selectedTarget) return;
    HapticFeedback.selectionClick();
    _commitTimer?.cancel();
    final prefs = ref.read(ledgerProvider).preferences;
    final optics = prefs.opticsFor(target);
    setState(() {
      _selectedTarget = target;
      _currentFinish = optics.finish;
      _blur = optics.blur;
      _backgroundOpacity = optics.backgroundOpacity;
      _refractionLevel = optics.refractionLevel;
      _specularOpacity = optics.specularOpacity;
    });
  }

  void _commitOpticsImmediately() {
    _commitTimer?.cancel();
    ref
        .read(ledgerProvider.notifier)
        .updatePreferencesWith(
          (live) => live.withComponentOptics(
            _selectedTarget,
            finish: _currentFinish,
            blur: _blur,
            backgroundOpacity: _backgroundOpacity,
            refractionLevel: _refractionLevel,
            specularOpacity: _specularOpacity,
          ),
        );
  }

  void _updateOptics({
    double? blur,
    double? opacity,
    double? refraction,
    double? specular,
  }) {
    setState(() {
      if (blur != null) _blur = blur;
      if (opacity != null) _backgroundOpacity = opacity;
      if (refraction != null) _refractionLevel = refraction;
      if (specular != null) _specularOpacity = specular;
    });

    _commitTimer?.cancel();
    _commitTimer = Timer(const Duration(milliseconds: 60), () {
      if (!mounted) return;
      ref
          .read(ledgerProvider.notifier)
          .updatePreferencesWith(
            (live) => live.withComponentOptics(
              _selectedTarget,
              finish: _currentFinish,
              blur: _blur,
              backgroundOpacity: _backgroundOpacity,
              refractionLevel: _refractionLevel,
              specularOpacity: _specularOpacity,
            ),
          );
    });
  }

  void _selectFinish(AppGlassFinish finish) {
    HapticFeedback.selectionClick();
    setState(() {
      _currentFinish = finish;
      _blur = finish.defaultBlur;
      _backgroundOpacity = finish.defaultBackgroundOpacity;
      _refractionLevel = finish.defaultRefractionLevel;
      _specularOpacity = finish.defaultSpecularOpacity;
    });
    _commitTimer?.cancel();
    ref
        .read(ledgerProvider.notifier)
        .updatePreferencesWith(
          (live) => live.withComponentOptics(
            _selectedTarget,
            finish: finish,
            blur: finish.defaultBlur,
            backgroundOpacity: finish.defaultBackgroundOpacity,
            refractionLevel: finish.defaultRefractionLevel,
            specularOpacity: finish.defaultSpecularOpacity,
          ),
        );
  }

  void _resetToDefaults() {
    HapticFeedback.mediumImpact();
    final defaultOptics = GlassComponentOptics.defaultFor(_selectedTarget);
    setState(() {
      _currentFinish = defaultOptics.finish;
      _blur = defaultOptics.blur;
      _backgroundOpacity = defaultOptics.backgroundOpacity;
      _refractionLevel = defaultOptics.refractionLevel;
      _specularOpacity = defaultOptics.specularOpacity;
    });
    _commitTimer?.cancel();
    ref
        .read(ledgerProvider.notifier)
        .updatePreferencesWith(
          (live) => live.resetComponentOptics(_selectedTarget),
        );
  }

  void _resetAllToDefaults() {
    HapticFeedback.heavyImpact();
    for (final target in GlassComponentTarget.values) {
      ref
          .read(ledgerProvider.notifier)
          .updatePreferencesWith((live) => live.resetComponentOptics(target));
    }
    final defaultOptics = GlassComponentOptics.defaultFor(_selectedTarget);
    setState(() {
      _currentFinish = defaultOptics.finish;
      _blur = defaultOptics.blur;
      _backgroundOpacity = defaultOptics.backgroundOpacity;
      _refractionLevel = defaultOptics.refractionLevel;
      _specularOpacity = defaultOptics.specularOpacity;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ledger = ref.watch(ledgerProvider);
    final themeState = ref.watch(themeControllerProvider);
    final isDark = themeState.preference != AppThemePreference.light;
    final scheme = Theme.of(context).colorScheme;

    // Sync from store if preference optics for selected target changed externally
    if (_initialized) {
      final liveOptics = ledger.preferences.opticsFor(_selectedTarget);
      if (_commitTimer == null || !_commitTimer!.isActive) {
        if (liveOptics.finish != _currentFinish ||
            (liveOptics.blur - _blur).abs() > 0.001 ||
            (liveOptics.backgroundOpacity - _backgroundOpacity).abs() > 0.001 ||
            (liveOptics.refractionLevel - _refractionLevel).abs() > 0.001 ||
            (liveOptics.specularOpacity - _specularOpacity).abs() > 0.001) {
          _currentFinish = liveOptics.finish;
          _blur = liveOptics.blur;
          _backgroundOpacity = liveOptics.backgroundOpacity;
          _refractionLevel = liveOptics.refractionLevel;
          _specularOpacity = liveOptics.specularOpacity;
        }
      }
    }

    final glassOptics = g1455.GlassOptics(
      strength: -58.2 * _refractionLevel,
      thickness:
          (21.0 *
          (_refractionLevel <= 0 ? 0.0 : _refractionLevel.clamp(0.2, 2.5))),
    );

    final resolvedFinish = switch (_currentFinish) {
      AppGlassFinish.regular =>
        g1455.GlassFinish.regular(
          appearance: isDark ? Brightness.dark : Brightness.light,
        ).copyWith(
          blurSigmaLogical: _blur,
          tint: isDark
              ? Color.fromRGBO(
                  255,
                  255,
                  255,
                  _backgroundOpacity.clamp(0.01, 0.90),
                )
              : Color.fromRGBO(
                  0,
                  0,
                  0,
                  (_backgroundOpacity * 0.7).clamp(0.01, 0.90),
                ),
          rim: isDark
              ? Color.fromRGBO(
                  255,
                  255,
                  255,
                  _specularOpacity.clamp(0.01, 0.95),
                )
              : Color.fromRGBO(
                  0,
                  0,
                  0,
                  (_specularOpacity * 0.5).clamp(0.01, 0.95),
                ),
          optics: glassOptics,
        ),
      AppGlassFinish.clear => g1455.GlassFinish.clear.copyWith(
        blurSigmaLogical: _blur,
        tint: isDark
            ? Color.fromRGBO(255, 255, 255, _backgroundOpacity.clamp(0.0, 0.90))
            : Color.fromRGBO(
                0,
                0,
                0,
                (_backgroundOpacity * 0.7).clamp(0.0, 0.90),
              ),
        rim: isDark
            ? Color.fromRGBO(255, 255, 255, _specularOpacity.clamp(0.01, 0.95))
            : Color.fromRGBO(
                0,
                0,
                0,
                (_specularOpacity * 0.5).clamp(0.01, 0.95),
              ),
        optics: glassOptics,
      ),
    };

    return RouteScaffold(
      title: 'Glass Effect',
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Component Target Selection Chips ──
              _ComponentSelector(
                selectedTarget: _selectedTarget,
                onSelected: _switchTarget,
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Live Interactive Glass Preview ──
              _LiveGlassPreview(
                target: _selectedTarget,
                finish: resolvedFinish,
                finishPref: _currentFinish,
                blur: _blur,
                backgroundOpacity: _backgroundOpacity,
                refractionLevel: _refractionLevel,
                specularOpacity: _specularOpacity,
                isDark: isDark,
                scheme: scheme,
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Glass Finish Presets (Clear vs Regular) ──
              AppGroupedSection(
                header: '${_selectedTarget.label} Finish',
                children: [
                  _GlassFinishOptionTile(
                    title: 'Clear',
                    subtitle:
                        'Crystal-clear optical liquid glass with zero blur & pure refraction',
                    icon: Icons.water_drop_outlined,
                    badge: 'Recommended',
                    isSelected: _currentFinish == AppGlassFinish.clear,
                    onTap: () => _selectFinish(AppGlassFinish.clear),
                  ),
                  const GlassDivider(),
                  _GlassFinishOptionTile(
                    title: 'Regular',
                    subtitle:
                        'Apple Liquid Glass with calibrated blur & adaptive transmission',
                    icon: Icons.blur_linear_outlined,
                    badge: 'Apple Standard',
                    isSelected: _currentFinish == AppGlassFinish.regular,
                    onTap: () => _selectFinish(AppGlassFinish.regular),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Interactive Optics Sliders ──
              AppGroupedSection(
                header: '${_selectedTarget.label} Optics Customization',
                children: [
                  // 1. Blur Radius Slider
                  _GlassSliderTile(
                    icon: Icons.blur_on_rounded,
                    title: 'Blur Radius',
                    subtitle: _blur == 0.0
                        ? 'Crystal clear (0 px) · Zero backdrop diffusion'
                        : 'Diffuses and softens backdrop elements behind surfaces',
                    valueDisplay: _blur == 0.0
                        ? '0 px (Sharp)'
                        : '${_blur.toStringAsFixed(1)} px',
                    value: _blur,
                    min: 0.0,
                    max: 35.0,
                    divisions: 70,
                    onChanged: (val) => _updateOptics(blur: val),
                    onChangeEnd: (_) => _commitOpticsImmediately(),
                  ),
                  const GlassDivider(),

                  // 2. Background Opacity Slider
                  _GlassSliderTile(
                    icon: Icons.opacity_rounded,
                    title: 'Background Opacity',
                    subtitle:
                        'Internal liquid tint density and light transmission',
                    valueDisplay: '${(_backgroundOpacity * 100).toInt()}%',
                    value: _backgroundOpacity,
                    min: 0.0,
                    max: 0.60,
                    divisions: 60,
                    onChanged: (val) => _updateOptics(opacity: val),
                    onChangeEnd: (_) => _commitOpticsImmediately(),
                  ),
                  const GlassDivider(),

                  // 3. Refraction Strength Slider
                  _GlassSliderTile(
                    icon: Icons.lens_blur_rounded,
                    title: 'Refraction Strength',
                    subtitle:
                        'Lens distortion curvature and refractive index scale',
                    valueDisplay: '${_refractionLevel.toStringAsFixed(2)}x',
                    value: _refractionLevel,
                    min: 0.0,
                    max: 2.0,
                    divisions: 40,
                    onChanged: (val) => _updateOptics(refraction: val),
                    onChangeEnd: (_) => _commitOpticsImmediately(),
                  ),
                  const GlassDivider(),

                  // 4. Rim Sheen / Specular Slider
                  _GlassSliderTile(
                    icon: Icons.auto_awesome_rounded,
                    title: 'Rim Sheen / Specular',
                    subtitle:
                        'Luminous caustic highlights along outer perimeter edges',
                    valueDisplay: '${(_specularOpacity * 100).toInt()}%',
                    value: _specularOpacity,
                    min: 0.0,
                    max: 1.0,
                    divisions: 50,
                    onChanged: (val) => _updateOptics(specular: val),
                    onChangeEnd: (_) => _commitOpticsImmediately(),
                  ),
                  const GlassDivider(),

                  // 5. Reset Current Target to Defaults Tile
                  AppGroupedTile(
                    leading: const Icon(Icons.restart_alt_rounded),
                    title: Text('Reset ${_selectedTarget.label} to Defaults'),
                    subtitle: Text(
                      'Restore default ${_selectedTarget.label.toLowerCase()} optic values',
                    ),
                    trailing: TextButton(
                      onPressed: _resetToDefaults,
                      child: const Text('Reset'),
                    ),
                    onTap: _resetToDefaults,
                  ),
                  const GlassDivider(),

                  // 6. Reset All Components Tile
                  AppGroupedTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('Reset All Components'),
                    subtitle: const Text(
                      'Restore factory defaults for island bar, FAB, dropdowns, toolbars & cards',
                    ),
                    trailing: TextButton(
                      onPressed: _resetAllToDefaults,
                      child: const Text('Reset all'),
                    ),
                    onTap: _resetAllToDefaults,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal segmented selector for choosing which UI component's liquid optics to customize.
class _ComponentSelector extends StatelessWidget {
  const _ComponentSelector({
    required this.selectedTarget,
    required this.onSelected,
  });

  final GlassComponentTarget selectedTarget;
  final ValueChanged<GlassComponentTarget> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: GlassComponentTarget.values.map((target) {
          final isSelected = target == selectedTarget;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => onSelected(target),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? scheme.primary.withAlphaFactor(isDark ? 0.28 : 0.18)
                        : (isDark
                              ? Colors.white.withAlphaFactor(0.06)
                              : Colors.black.withAlphaFactor(0.04)),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? scheme.primary
                          : (isDark
                                ? Colors.white.withAlphaFactor(0.12)
                                : Colors.black.withAlphaFactor(0.08)),
                      width: isSelected ? 1.5 : 1.0,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: scheme.primary.withAlphaFactor(0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        target.icon,
                        size: 18,
                        color: isSelected
                            ? scheme.primary
                            : (isDark ? Colors.white70 : Colors.black54),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        target.shortLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: isSelected
                              ? scheme.primary
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _GlassSliderTile extends StatelessWidget {
  const _GlassSliderTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.valueDisplay,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    this.onChangeEnd,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String valueDisplay;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: scheme.primary.withAlphaFactor(0.16),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: scheme.primary.withAlphaFactor(0.35),
                  ),
                ),
                child: Text(
                  valueDisplay,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 30),
            child: Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: scheme.primary,
              inactiveTrackColor: scheme.primary.withAlphaFactor(0.20),
              thumbColor: scheme.primary,
              overlayColor: scheme.primary.withAlphaFactor(0.15),
              trackHeight: 4,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveGlassPreview extends StatelessWidget {
  const _LiveGlassPreview({
    required this.target,
    required this.finish,
    required this.finishPref,
    required this.blur,
    required this.backgroundOpacity,
    required this.refractionLevel,
    required this.specularOpacity,
    required this.isDark,
    required this.scheme,
  });

  final GlassComponentTarget target;
  final g1455.GlassFinish finish;
  final AppGlassFinish finishPref;
  final double blur;
  final double backgroundOpacity;
  final double refractionLevel;
  final double specularOpacity;
  final bool isDark;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final fillAlphaTop = backgroundOpacity.clamp(0.01, 0.85);
    final fillAlphaBottom = (fillAlphaTop * 0.45).clamp(0.005, 0.70);
    final borderAlpha = specularOpacity.clamp(0.10, 0.95);

    return Container(
      height: 260,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withAlphaFactor(isDark ? 0.12 : 0.25),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlphaFactor(isDark ? 0.45 : 0.15),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Background Finance Scene with Colorful Elements ──
          Positioned.fill(
            child: ColoredBox(
              color: isDark ? const Color(0xFF0F1017) : const Color(0xFFE8E9F0),
              child: Stack(
                children: [
                  Positioned(
                    top: -40,
                    left: -30,
                    width: 200,
                    height: 200,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF2979FF).withAlphaFactor(0.85),
                            const Color(0x002979FF),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: -40,
                    right: -20,
                    width: 220,
                    height: 220,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFFFF1744).withAlphaFactor(0.80),
                            const Color(0x00FF1744),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 20,
                    right: 40,
                    width: 160,
                    height: 160,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF00E676).withAlphaFactor(0.75),
                            const Color(0x0000E676),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Top Header inside preview scene
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 16,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF00E676),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${target.label.toUpperCase()} PREVIEW',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withAlphaFactor(
                              isDark ? 0.10 : 0.40,
                            ),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withAlphaFactor(
                                isDark ? 0.20 : 0.60,
                              ),
                            ),
                          ),
                          child: Text(
                            '${finishPref.label.toUpperCase()} · ${blur == 0 ? "0PX" : "${blur.toStringAsFixed(1)}PX"} · ${(backgroundOpacity * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.8,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Account Cards in the background scene
                  Positioned(
                    top: 40,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 100,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF1976D2), Color(0xFF0D47A1)],
                              ),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.credit_card_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                Spacer(),
                                Text(
                                  'Checking',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white70,
                                  ),
                                ),
                                Text(
                                  '\$1,460.00',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 100,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF00C853), Color(0xFF007E33)],
                              ),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.account_balance_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                Spacer(),
                                Text(
                                  'Savings',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white70,
                                  ),
                                ),
                                Text(
                                  '+\$7,370.00',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            height: 100,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFFFF3D00), Color(0xFFDD2C00)],
                              ),
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.shopping_bag_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                Spacer(),
                                Text(
                                  'Groceries',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white70,
                                  ),
                                ),
                                Text(
                                  '-\$96.50',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Chart bars spanning across the middle
                  Positioned(
                    top: 136,
                    left: 20,
                    right: 20,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        for (final bar in [
                          (const Color(0xFF00E676), 28.0),
                          (const Color(0xFF2979FF), 42.0),
                          (const Color(0xFFFF9100), 18.0),
                          (const Color(0xFFE040FB), 36.0),
                          (const Color(0xFFFF1744), 24.0),
                          (const Color(0xFF00E5FF), 48.0),
                        ])
                          Container(
                            width: 14,
                            height: bar.$2,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: bar.$1,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── The Specific Target Component's Live Glass Preview Floating in Front ──
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: _buildComponentSpecificPreview(
              context,
              fillAlphaTop: fillAlphaTop,
              fillAlphaBottom: fillAlphaBottom,
              borderAlpha: borderAlpha,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComponentSpecificPreview(
    BuildContext context, {
    required double fillAlphaTop,
    required double fillAlphaBottom,
    required double borderAlpha,
  }) {
    switch (target) {
      case GlassComponentTarget.islandBar:
        return _buildIslandBarPreview(
          context,
          fillAlphaTop: fillAlphaTop,
          fillAlphaBottom: fillAlphaBottom,
          borderAlpha: borderAlpha,
        );
      case GlassComponentTarget.fab:
        return _buildFabPreview(
          context,
          fillAlphaTop: fillAlphaTop,
          fillAlphaBottom: fillAlphaBottom,
          borderAlpha: borderAlpha,
        );
      case GlassComponentTarget.dropdownMenu:
        return _buildDropdownPreview(
          context,
          fillAlphaTop: fillAlphaTop,
          fillAlphaBottom: fillAlphaBottom,
          borderAlpha: borderAlpha,
        );
      case GlassComponentTarget.toolbars:
        return _buildToolbarsPreview(
          context,
          fillAlphaTop: fillAlphaTop,
          fillAlphaBottom: fillAlphaBottom,
          borderAlpha: borderAlpha,
        );
      case GlassComponentTarget.general:
        return _buildGeneralCardPreview(
          context,
          fillAlphaTop: fillAlphaTop,
          fillAlphaBottom: fillAlphaBottom,
          borderAlpha: borderAlpha,
        );
    }
  }

  Widget _buildIslandBarPreview(
    BuildContext context, {
    required double fillAlphaTop,
    required double fillAlphaBottom,
    required double borderAlpha,
  }) {
    final custom =
        Theme.of(context).extension<AppThemeCustomization>() ??
        const AppThemeCustomization();
    final borderWidth = custom.outlineThickness > 0
        ? (custom.outlineThickness * 0.75).clamp(0.2, 1.2)
        : 0.0;
    final borderColor = (isDark ? Colors.white : scheme.outlineVariant)
        .withAlphaFactor((custom.outlineOpacity * 0.7).clamp(0.04, 0.40));
    final pillRadius = BorderRadius.circular(30);

    return g1455.GlassSurface(
      borderRadius: pillRadius,
      finish: finish,
      labelled: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: pillRadius,
          border: borderWidth > 0
              ? Border.all(color: borderColor, width: borderWidth)
              : null,
        ),
        child: Container(
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _navPreviewItem(Icons.home_rounded, 'Home', true),
              _navPreviewItem(Icons.receipt_long_rounded, 'Records', false),
              _navPreviewItem(Icons.calendar_month_rounded, 'Calendar', false),
              _navPreviewItem(Icons.wallet_rounded, 'Accounts', false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navPreviewItem(IconData icon, String label, bool active) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: active
          ? BoxDecoration(
              color: scheme.primary.withAlphaFactor(0.20),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.primary.withAlphaFactor(0.35)),
            )
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 20,
            color: active
                ? scheme.primary
                : (isDark ? Colors.white60 : Colors.black54),
          ),
          if (active) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: scheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFabPreview(
    BuildContext context, {
    required double fillAlphaTop,
    required double fillAlphaBottom,
    required double borderAlpha,
  }) {
    final custom =
        Theme.of(context).extension<AppThemeCustomization>() ??
        const AppThemeCustomization();
    final fabBorderWidth = custom.outlineThickness > 0
        ? (custom.outlineThickness * 0.8).clamp(0.2, 1.2)
        : 0.0;
    final fabBorderColor = scheme.primary.withAlphaFactor(
      (custom.outlineOpacity * 0.8).clamp(0.04, 0.40),
    );
    final circleRadius = BorderRadius.circular(32);

    return Center(
      child: g1455.GlassSurface(
        borderRadius: circleRadius,
        finish: finish,
        labelled: false,
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: fabBorderWidth > 0
                ? Border.all(color: fabBorderColor, width: fabBorderWidth)
                : null,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary.withAlphaFactor(isDark ? 0.48 : 0.40),
                Color.lerp(
                  scheme.primary,
                  isDark ? Colors.black : Colors.black87,
                  0.28,
                )!.withAlphaFactor(isDark ? 0.36 : 0.30),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withAlphaFactor(isDark ? 0.25 : 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.add_rounded, color: Colors.white, size: 32),
        ),
      ),
    );
  }

  Widget _buildDropdownPreview(
    BuildContext context, {
    required double fillAlphaTop,
    required double fillAlphaBottom,
    required double borderAlpha,
  }) {
    final custom =
        Theme.of(context).extension<AppThemeCustomization>() ??
        const AppThemeCustomization();
    final borderWidth = custom.outlineThickness > 0
        ? (custom.outlineThickness * 0.75).clamp(0.2, 1.2)
        : 0.0;
    final borderColor = (isDark ? Colors.white : scheme.outlineVariant)
        .withAlphaFactor((custom.outlineOpacity * 0.7).clamp(0.04, 0.40));
    final menuRadius = BorderRadius.circular(16);

    return g1455.GlassSurface(
      borderRadius: menuRadius,
      finish: finish,
      labelled: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: menuRadius,
          border: borderWidth > 0
              ? Border.all(color: borderColor, width: borderWidth)
              : null,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _menuPreviewOption(
                Icons.add_circle_outline_rounded,
                'Add record',
              ),
              Container(
                width: 1,
                height: 24,
                color: (isDark ? Colors.white : Colors.black).withAlphaFactor(
                  0.15,
                ),
              ),
              _menuPreviewOption(
                Icons.document_scanner_outlined,
                'Scan receipt',
              ),
              Container(
                width: 1,
                height: 24,
                color: (isDark ? Colors.white : Colors.black).withAlphaFactor(
                  0.15,
                ),
              ),
              _menuPreviewOption(Icons.file_download_outlined, 'Export CSV'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuPreviewOption(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  Widget _buildToolbarsPreview(
    BuildContext context, {
    required double fillAlphaTop,
    required double fillAlphaBottom,
    required double borderAlpha,
  }) {
    final custom =
        Theme.of(context).extension<AppThemeCustomization>() ??
        const AppThemeCustomization();
    final borderWidth = custom.outlineThickness > 0
        ? (custom.outlineThickness * 0.75).clamp(0.2, 1.2)
        : 0.0;
    final borderColor = (isDark ? Colors.white : scheme.outlineVariant)
        .withAlphaFactor((custom.outlineOpacity * 0.7).clamp(0.04, 0.40));
    final toolbarRadius = BorderRadius.circular(18);

    return g1455.GlassSurface(
      borderRadius: toolbarRadius,
      finish: finish,
      labelled: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: toolbarRadius,
          border: borderWidth > 0
              ? Border.all(color: borderColor, width: borderWidth)
              : null,
        ),
        child: Container(
          height: 52,
          padding: const EdgeInsets.all(4),
          child: Row(
            children: [
              _toolbarSegment('All', true),
              _toolbarSegment('Income', false),
              _toolbarSegment('Expense', false),
              _toolbarSegment('Transfer', false),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolbarSegment(String title, bool isSelected) {
    return Expanded(
      child: Container(
        alignment: Alignment.center,
        decoration: isSelected
            ? BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withAlphaFactor(0.30),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              )
            : null,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            color: isSelected
                ? Colors.white
                : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildGeneralCardPreview(
    BuildContext context, {
    required double fillAlphaTop,
    required double fillAlphaBottom,
    required double borderAlpha,
  }) {
    final custom =
        Theme.of(context).extension<AppThemeCustomization>() ??
        const AppThemeCustomization();
    final borderWidth = custom.outlineThickness > 0
        ? (custom.outlineThickness * 0.75).clamp(0.2, 1.2)
        : 0.0;
    final borderColor = (isDark ? Colors.white : scheme.outlineVariant)
        .withAlphaFactor((custom.outlineOpacity * 0.7).clamp(0.04, 0.40));
    final cardRadius = BorderRadius.circular(20);

    return g1455.GlassSurface(
      borderRadius: cardRadius,
      finish: finish,
      labelled: false,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: cardRadius,
          border: borderWidth > 0
              ? Border.all(color: borderColor, width: borderWidth)
              : null,
        ),
        child: Container(
          height: 78,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      scheme.primary.withAlphaFactor(0.85),
                      scheme.primary.withAlphaFactor(0.40),
                    ],
                  ),
                ),
                child: Icon(
                  switch (finishPref) {
                    AppGlassFinish.clear => Icons.water_drop_rounded,
                    AppGlassFinish.regular => Icons.blur_linear_rounded,
                  },
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          finishPref.label,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withAlphaFactor(0.20),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            blur == 0
                                ? '0px Blur · Sharp'
                                : '${blur.toStringAsFixed(1)}px Blur · ${(backgroundOpacity * 100).toInt()}% Opacity',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      switch (finishPref) {
                        AppGlassFinish.clear =>
                          'Crystal clear liquid glass with zero blur',
                        AppGlassFinish.regular =>
                          'Calibrated liquid blur with dynamic refraction',
                      },
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassFinishOptionTile extends StatelessWidget {
  const _GlassFinishOptionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    this.badge,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppGroupedTile(
      leading: Icon(icon, color: isSelected ? scheme.primary : null),
      title: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
          if (badge != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
              decoration: BoxDecoration(
                color: isSelected
                    ? scheme.primary.withAlphaFactor(0.20)
                    : Colors.white.withAlphaFactor(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isSelected
                      ? scheme.primary.withAlphaFactor(0.40)
                      : Colors.white.withAlphaFactor(0.15),
                ),
              ),
              child: Text(
                badge!,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? scheme.primary : Colors.white70,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(subtitle),
      trailing: isSelected
          ? Icon(Icons.check_circle_rounded, color: scheme.primary)
          : null,
      onTap: onTap,
    );
  }
}
