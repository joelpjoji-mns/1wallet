import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../design/tokens.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';

/// Screen allowing the user to configure theme mode (Light, Dark AMOLED, System),
/// choose between dynamic system wallpaper color or custom accent colors,
/// and adjust color intensity with a live real-time preview.
class ThemeModeScreen extends ConsumerStatefulWidget {
  const ThemeModeScreen({super.key});

  @override
  ConsumerState<ThemeModeScreen> createState() => _ThemeModeScreenState();
}

class _ThemeModeScreenState extends ConsumerState<ThemeModeScreen> {
  late double _intensity;
  late double _surfaceContrast;
  late double _outlineThickness;
  late double _outlineOpacity;
  bool _sliderActive = false;
  bool _contrastSliderActive = false;
  bool _thicknessSliderActive = false;
  bool _opacitySliderActive = false;

  @override
  void initState() {
    super.initState();
    final theme = ref.read(themeControllerProvider);
    _intensity = theme.colorIntensity;
    _surfaceContrast = theme.surfaceContrast;
    _outlineThickness = theme.outlineThickness;
    _outlineOpacity = theme.outlineOpacity;
  }

  void _onIntensityChanged(double value) {
    setState(() {
      _intensity = value;
      _sliderActive = true;
    });
    ref
        .read(themeControllerProvider.notifier)
        .setColorIntensity(value, persist: false);
  }

  void _onIntensityChangeEnd(double value) {
    setState(() {
      _intensity = value;
      _sliderActive = false;
    });
    ref
        .read(themeControllerProvider.notifier)
        .setColorIntensity(value, persist: true);
  }

  void _onContrastChanged(double value) {
    setState(() {
      _surfaceContrast = value;
      _contrastSliderActive = true;
    });
    ref
        .read(themeControllerProvider.notifier)
        .setSurfaceContrast(value, persist: false);
  }

  void _onContrastChangeEnd(double value) {
    setState(() {
      _surfaceContrast = value;
      _contrastSliderActive = false;
    });
    ref
        .read(themeControllerProvider.notifier)
        .setSurfaceContrast(value, persist: true);
  }

  void _onThicknessChanged(double value) {
    setState(() {
      _outlineThickness = value;
      _thicknessSliderActive = true;
    });
    ref
        .read(themeControllerProvider.notifier)
        .setOutlineThickness(value, persist: false);
  }

  void _onThicknessChangeEnd(double value) {
    setState(() {
      _outlineThickness = value;
      _thicknessSliderActive = false;
    });
    ref
        .read(themeControllerProvider.notifier)
        .setOutlineThickness(value, persist: true);
  }

  void _onOpacityChanged(double value) {
    setState(() {
      _outlineOpacity = value;
      _opacitySliderActive = true;
    });
    ref
        .read(themeControllerProvider.notifier)
        .setOutlineOpacity(value, persist: false);
  }

  void _onOpacityChangeEnd(double value) {
    setState(() {
      _outlineOpacity = value;
      _opacitySliderActive = false;
    });
    ref
        .read(themeControllerProvider.notifier)
        .setOutlineOpacity(value, persist: true);
  }

  Future<void> _resetTheme() async {
    HapticFeedback.selectionClick();
    await ref.read(themeControllerProvider.notifier).resetToDefaults();
    if (!mounted) return;
    showAppSnackBar(context, 'Theme reset to default.');
  }

  Future<void> _showCustomColorDialog() async {
    final controller = TextEditingController();
    String? errorText;

    final color = await showDialog<Color>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            title: const Text('Custom accent color'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Enter a 6-digit hexadecimal color code (e.g. 007AFF or FA233B):',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLength: 7,
                  decoration: InputDecoration(
                    prefixText: '#',
                    hintText: 'FA233B',
                    errorText: errorText,
                  ),
                  onChanged: (val) {
                    final clean = val.replaceAll('#', '').trim();
                    if (clean.length == 6) {
                      final parsed = int.tryParse(clean, radix: 16);
                      if (parsed == null) {
                        setDialogState(() => errorText = 'Invalid hex color');
                      } else {
                        setDialogState(() => errorText = null);
                      }
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final clean = controller.text.replaceAll('#', '').trim();
                  final parsed = int.tryParse(clean, radix: 16);
                  if (clean.length == 6 && parsed != null) {
                    final r = (parsed >> 16) & 0xFF;
                    final g = (parsed >> 8) & 0xFF;
                    final b = parsed & 0xFF;
                    Navigator.of(ctx).pop(Color.fromARGB(255, r, g, b));
                  } else {
                    setDialogState(() => errorText = 'Enter 6 hex characters');
                  }
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      ),
    );

    if (color == null || !mounted) return;
    HapticFeedback.selectionClick();
    await ref
        .read(themeControllerProvider.notifier)
        .setCustomAccentColor(color);
    if (!mounted) return;
    showAppSnackBar(context, 'Custom accent color applied.');
  }

  @override
  Widget build(BuildContext context) {
    final themeState = ref.watch(themeControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    if (!_sliderActive && _intensity != themeState.colorIntensity) {
      _intensity = themeState.colorIntensity;
    }
    if (!_contrastSliderActive &&
        _surfaceContrast != themeState.surfaceContrast) {
      _surfaceContrast = themeState.surfaceContrast;
    }
    if (!_thicknessSliderActive &&
        _outlineThickness != themeState.outlineThickness) {
      _outlineThickness = themeState.outlineThickness;
    }
    if (!_opacitySliderActive && _outlineOpacity != themeState.outlineOpacity) {
      _outlineOpacity = themeState.outlineOpacity;
    }

    final modeLabel = switch (themeState.preference) {
      AppThemePreference.system => 'System',
      AppThemePreference.light => 'Light',
      AppThemePreference.amoled => 'Dark (AMOLED)',
    };

    final intensityPercent = (_intensity * 100).round();
    final contrastPercent = (_surfaceContrast * 100).round();
    final opacityPercent = (_outlineOpacity * 100).round();

    return RouteScaffold(
      title: 'Theme & Appearance',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Real-time Interactive Live Preview ──
          _ThemeLivePreview(
            modeLabel: modeLabel,
            intensityPercent: intensityPercent,
            useSystemColor: themeState.useSystemColor,
            contrastPercent: contrastPercent,
            outlineThickness: _outlineThickness,
            outlineOpacity: _outlineOpacity,
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Theme Mode ──
          AppGroupedSection(
            header: 'Theme mode',
            children: [
              _ModeTile(
                icon: Icons.brightness_auto_outlined,
                title: 'System',
                subtitle: 'Match device dark or light mode setting',
                selected: themeState.preference == AppThemePreference.system,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref
                      .read(themeControllerProvider.notifier)
                      .setPreference(AppThemePreference.system);
                },
              ),
              const GlassDivider(),
              _ModeTile(
                icon: Icons.light_mode_outlined,
                title: 'Light',
                subtitle: 'Crisp, high-clarity Material 3 surfaces',
                selected: themeState.preference == AppThemePreference.light,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref
                      .read(themeControllerProvider.notifier)
                      .setPreference(AppThemePreference.light);
                },
              ),
              const GlassDivider(),
              _ModeTile(
                icon: Icons.dark_mode_outlined,
                title: 'Dark (AMOLED)',
                subtitle:
                    'Pitch-black OLED surfaces for maximum battery saving',
                selected: themeState.preference == AppThemePreference.amoled,
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref
                      .read(themeControllerProvider.notifier)
                      .setPreference(AppThemePreference.amoled);
                },
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Color Source & Accent Color ──
          AppGroupedSection(
            header: 'Accent color',
            children: [
              AppGroupedTile.toggle(
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('Match system wallpaper'),
                subtitle: const Text(
                  'Extract dynamic colors from your device (Material You)',
                ),
                value: themeState.useSystemColor,
                onChanged: (value) {
                  HapticFeedback.selectionClick();
                  ref
                      .read(themeControllerProvider.notifier)
                      .setUseSystemColor(value);
                },
              ),
              const GlassDivider(),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      themeState.useSystemColor
                          ? 'Choose a custom swatch below to override system wallpaper colors:'
                          : 'Select an accent color palette:',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final option in AppThemeAccents.options)
                          _AccentSwatch(
                            color: option.color,
                            name: option.name,
                            selected:
                                !themeState.useSystemColor &&
                                (themeState.customAccentColor?.toARGB32() ==
                                        option.color.toARGB32() ||
                                    (themeState.customAccentColor == null &&
                                        option.color ==
                                            AppThemeAccents.crimson)),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              ref
                                  .read(themeControllerProvider.notifier)
                                  .setCustomAccentColor(option.color);
                            },
                          ),
                        _CustomColorButton(onTap: _showCustomColorDialog),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Color Intensity Slider ──
          AppGroupedSection(
            header: 'Color intensity',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.tonality_rounded,
                          size: 20,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            'Vibrancy & Saturation',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: AppSpacing.xxxs,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withAlphaFactor(0.16),
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            border: Border.all(
                              color: scheme.primary.withAlphaFactor(0.35),
                            ),
                          ),
                          child: Text(
                            '$intensityPercent%',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.primary,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Padding(
                      padding: const EdgeInsets.only(left: 28),
                      child: Text(
                        'Control the punch and saturation of accent surfaces and highlights.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: scheme.primary,
                        inactiveTrackColor: scheme.primary.withAlphaFactor(
                          0.20,
                        ),
                        thumbColor: scheme.primary,
                        overlayColor: scheme.primary.withAlphaFactor(0.15),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _intensity.clamp(0.0, 1.8),
                        min: 0.0,
                        max: 1.8,
                        divisions: 18,
                        onChanged: _onIntensityChanged,
                        onChangeEnd: _onIntensityChangeEnd,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _IntensityPresetChip(
                          label: 'Subtle (50%)',
                          selected: (_intensity - 0.5).abs() < 0.05,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _onIntensityChangeEnd(0.5);
                          },
                        ),
                        _IntensityPresetChip(
                          label: 'Default (100%)',
                          selected: (_intensity - 1.0).abs() < 0.05,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _onIntensityChangeEnd(1.0);
                          },
                        ),
                        _IntensityPresetChip(
                          label: 'Vibrant (150%)',
                          selected: (_intensity - 1.5).abs() < 0.05,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _onIntensityChangeEnd(1.5);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Dark Surface & Card Contrast Slider ──
          AppGroupedSection(
            header: 'Dark surface contrast',
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.contrast_rounded,
                          size: 20,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            'Card & Surface Elevation',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: AppSpacing.xxxs,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withAlphaFactor(0.16),
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            border: Border.all(
                              color: scheme.primary.withAlphaFactor(0.35),
                            ),
                          ),
                          child: Text(
                            '$contrastPercent%',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.primary,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Padding(
                      padding: const EdgeInsets.only(left: 28),
                      child: Text(
                        _surfaceContrast == 0.0
                            ? 'Pure black (0%) · Cards match background seamlessly'
                            : 'Adjusts grey elevation of cards and widgets in dark mode.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: scheme.primary,
                        inactiveTrackColor: scheme.primary.withAlphaFactor(
                          0.20,
                        ),
                        thumbColor: scheme.primary,
                        overlayColor: scheme.primary.withAlphaFactor(0.15),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _surfaceContrast.clamp(0.0, 1.8),
                        min: 0.0,
                        max: 1.8,
                        divisions: 18,
                        onChanged: _onContrastChanged,
                        onChangeEnd: _onContrastChangeEnd,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _IntensityPresetChip(
                          label: 'Pure black (0%)',
                          selected: _surfaceContrast == 0.0,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _onContrastChangeEnd(0.0);
                          },
                        ),
                        _IntensityPresetChip(
                          label: 'Subtle (60%)',
                          selected: (_surfaceContrast - 0.6).abs() < 0.05,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _onContrastChangeEnd(0.6);
                          },
                        ),
                        _IntensityPresetChip(
                          label: 'Default (100%)',
                          selected: (_surfaceContrast - 1.0).abs() < 0.05,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _onContrastChangeEnd(1.0);
                          },
                        ),
                        _IntensityPresetChip(
                          label: 'High (150%)',
                          selected: (_surfaceContrast - 1.5).abs() < 0.05,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _onContrastChangeEnd(1.5);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Outline & Borders Customization ──
          AppGroupedSection(
            header: 'Card & component outlines',
            children: [
              // 1. Thickness
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.line_weight_rounded,
                          size: 20,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            'Outline thickness',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: AppSpacing.xxxs,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withAlphaFactor(0.16),
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            border: Border.all(
                              color: scheme.primary.withAlphaFactor(0.35),
                            ),
                          ),
                          child: Text(
                            _outlineThickness == 0.0
                                ? 'Off'
                                : '${_outlineThickness.toStringAsFixed(1)} px',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.primary,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Padding(
                      padding: const EdgeInsets.only(left: 28),
                      child: Text(
                        'Border thickness for cards, island bar, and floating buttons.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: scheme.primary,
                        inactiveTrackColor: scheme.primary.withAlphaFactor(
                          0.20,
                        ),
                        thumbColor: scheme.primary,
                        overlayColor: scheme.primary.withAlphaFactor(0.15),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _outlineThickness.clamp(0.0, 2.0),
                        min: 0.0,
                        max: 2.0,
                        divisions: 20,
                        onChanged: _onThicknessChanged,
                        onChangeEnd: _onThicknessChangeEnd,
                      ),
                    ),
                  ],
                ),
              ),
              const GlassDivider(),

              // 2. Opacity / Transparency
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.opacity_rounded,
                          size: 20,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            'Outline opacity & transparency',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xs,
                            vertical: AppSpacing.xxxs,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary.withAlphaFactor(0.16),
                            borderRadius: BorderRadius.circular(AppRadii.sm),
                            border: Border.all(
                              color: scheme.primary.withAlphaFactor(0.35),
                            ),
                          ),
                          child: Text(
                            '$opacityPercent%',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: scheme.primary,
                                ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Padding(
                      padding: const EdgeInsets.only(left: 28),
                      child: Text(
                        'Border visibility across cards, bottom island bar, and floating button.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        activeTrackColor: scheme.primary,
                        inactiveTrackColor: scheme.primary.withAlphaFactor(
                          0.20,
                        ),
                        thumbColor: scheme.primary,
                        overlayColor: scheme.primary.withAlphaFactor(0.15),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _outlineOpacity.clamp(0.0, 1.0),
                        min: 0.0,
                        max: 1.0,
                        divisions: 20,
                        onChanged: _onOpacityChanged,
                        onChangeEnd: _onOpacityChangeEnd,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Reset to Defaults ──
          AppGroupedSection(
            header: 'Defaults',
            children: [
              AppGroupedTile(
                leading: const Icon(Icons.restart_alt_rounded),
                title: const Text('Reset theme settings'),
                subtitle: const Text(
                  'Restore Dark AMOLED, Apple Music Red, and 100% intensity',
                ),
                onTap: _resetTheme,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxl),
        ],
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AppGroupedTile(
      leading: Icon(
        icon,
        color: selected ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: selected
          ? Icon(Icons.check_rounded, color: scheme.primary)
          : null,
      onTap: onTap,
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? Colors.white : Colors.transparent,
              width: selected ? 3.0 : 1.0,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: color.withAlphaFactor(0.40),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: selected
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 22)
              : null,
        ),
      ),
    );
  }
}

class _CustomColorButton extends StatelessWidget {
  const _CustomColorButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Tooltip(
      message: 'Custom hex color',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: scheme.surfaceContainerHighest,
            border: Border.all(color: scheme.outlineVariant, width: 1.5),
          ),
          child: Icon(
            Icons.colorize_rounded,
            size: 20,
            color: scheme.onSurface,
          ),
        ),
      ),
    );
  }
}

class _IntensityPresetChip extends StatelessWidget {
  const _IntensityPresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.pill),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withAlphaFactor(0.18)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadii.pill),
          border: Border.all(
            color: selected
                ? scheme.primary
                : scheme.outlineVariant.withAlphaFactor(0.5),
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ThemeLivePreview extends StatelessWidget {
  const _ThemeLivePreview({
    required this.modeLabel,
    required this.intensityPercent,
    required this.useSystemColor,
    required this.contrastPercent,
    required this.outlineThickness,
    required this.outlineOpacity,
  });

  final String modeLabel;
  final int intensityPercent;
  final bool useSystemColor;
  final int contrastPercent;
  final double outlineThickness;
  final double outlineOpacity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final customBorderColor = (isDark ? Colors.white : scheme.outlineVariant)
        .withAlphaFactor(outlineOpacity.clamp(0.0, 1.0));

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(
          color: scheme.primary.withAlphaFactor(0.30),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Live Preview',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs,
                  vertical: AppSpacing.xxxs,
                ),
                decoration: BoxDecoration(
                  color: scheme.primary.withAlphaFactor(0.16),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: Text(
                  '$modeLabel · $contrastPercent% Depth · ${outlineThickness.toStringAsFixed(1)}px Border',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Mini account balance card (using actual surfaceContainerLow)
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: outlineThickness > 0
                  ? Border.all(
                      color: customBorderColor,
                      width: outlineThickness,
                    )
                  : null,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Total Balance',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                        vertical: AppSpacing.xxxs,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withAlphaFactor(0.20),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.trending_up_rounded,
                            size: 14,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: AppSpacing.xxs),
                          Text(
                            '+12.4%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  '\$12,450.00',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: scheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Component & Island Bar live preview strip
          Row(
            children: [
              // Mini Island Bar Capsule
              Expanded(
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh.withAlphaFactor(
                      isDark ? 0.35 : 0.65,
                    ),
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: outlineThickness > 0
                        ? Border.all(
                            color: customBorderColor,
                            width: (outlineThickness * 0.75).clamp(0.2, 1.2),
                          )
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Icon(Icons.home_rounded, size: 18, color: scheme.primary),
                      Icon(
                        Icons.receipt_long_rounded,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      Icon(
                        Icons.wallet_rounded,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),

              // Mini Action Button (FAB)
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primary,
                  border: outlineThickness > 0
                      ? Border.all(
                          color: (isDark ? Colors.white : Colors.black)
                              .withAlphaFactor(
                                (outlineOpacity * 0.8).clamp(0.04, 0.40),
                              ),
                          width: (outlineThickness * 0.8).clamp(0.2, 1.2),
                        )
                      : null,
                  boxShadow: [
                    BoxShadow(
                      color: scheme.primary.withAlphaFactor(0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
