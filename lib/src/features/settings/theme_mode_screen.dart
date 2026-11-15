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
  bool _sliderActive = false;

  @override
  void initState() {
    super.initState();
    _intensity = ref.read(themeControllerProvider).colorIntensity;
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

  Future<void> _resetTheme() async {
    HapticFeedback.selectionClick();
    await ref
        .read(themeControllerProvider.notifier)
        .resetToDefaults();
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

    final modeLabel = switch (themeState.preference) {
      AppThemePreference.system => 'System',
      AppThemePreference.light => 'Light',
      AppThemePreference.amoled => 'Dark (AMOLED)',
    };

    final intensityPercent = (_intensity * 100).round();

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
                subtitle: 'Pitch-black OLED surfaces for maximum battery saving',
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
                            selected: !themeState.useSystemColor &&
                                (themeState.customAccentColor?.toARGB32() ==
                                        option.color.toARGB32() ||
                                    (themeState.customAccentColor == null &&
                                        option.color == AppThemeAccents.crimson)),
                            onTap: () {
                              HapticFeedback.selectionClick();
                              ref
                                  .read(themeControllerProvider.notifier)
                                  .setCustomAccentColor(option.color);
                            },
                          ),
                        _CustomColorButton(
                          onTap: _showCustomColorDialog,
                        ),
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
                        inactiveTrackColor:
                            scheme.primary.withAlphaFactor(0.20),
                        thumbColor: scheme.primary,
                        overlayColor: scheme.primary.withAlphaFactor(0.15),
                        trackHeight: 4,
                      ),
                      child: Slider(
                        value: _intensity.clamp(0.2, 1.8),
                        min: 0.2,
                        max: 1.8,
                        divisions: 16,
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
              ? const Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 22,
                )
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
            border: Border.all(
              color: scheme.outlineVariant,
              width: 1.5,
            ),
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
  });

  final String modeLabel;
  final int intensityPercent;
  final bool useSystemColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadii.xl),
        border: Border.all(
          color: scheme.primary.withAlphaFactor(0.25),
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
                  '$modeLabel · ${useSystemColor ? 'System' : 'Custom'} · $intensityPercent%',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // Mini account balance card
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primary.withAlphaFactor(isDark ? 0.28 : 0.16),
                  scheme.surfaceContainerHigh,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(
                color: scheme.primary.withAlphaFactor(0.30),
              ),
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

          // Interactive controls preview
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {},
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('New record'),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: scheme.tertiary.withAlphaFactor(0.20),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(
                    color: scheme.tertiary.withAlphaFactor(0.40),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.arrow_downward_rounded,
                      size: 16,
                      color: scheme.tertiary,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      'Income',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: scheme.tertiary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
