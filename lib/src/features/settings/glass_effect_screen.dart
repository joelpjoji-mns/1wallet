import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart' as g1455;
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../theme/theme_controller.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';

/// Screen allowing the user to customize the application's liquid glass finish
/// (Regular, Clear, Frosted) and intensity (Light, Medium, Heavy) with an
/// interactive real-time live preview.
class GlassEffectScreen extends ConsumerWidget {
  const GlassEffectScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ledger = ref.watch(ledgerProvider);
    final currentFinish = ledger.preferences.glassFinish;
    final currentIntensity = ledger.preferences.glassIntensity;
    final themeState = ref.watch(themeControllerProvider);
    final isDark = themeState.preference != AppThemePreference.light;
    final scheme = Theme.of(context).colorScheme;

    final blur = currentFinish.blurForIntensity(currentIntensity);

    final fillAlpha = currentFinish.backgroundOpacity(
      intensity: currentIntensity,
      isDark: isDark,
    );

    final resolvedFinish = switch (currentFinish) {
      AppGlassFinish.regular => g1455.GlassFinish.regular(
          appearance: isDark ? Brightness.dark : Brightness.light,
        ).copyWith(blurSigmaLogical: blur),
      AppGlassFinish.clear => g1455.GlassFinish.clear.copyWith(
          blurSigmaLogical: 0.0,
          tint: Color.fromRGBO(255, 255, 255, fillAlpha),
        ),
      AppGlassFinish.frosted => g1455.GlassFinish.frosted.copyWith(
          blurSigmaLogical: blur,
          tint: Color.fromRGBO(255, 255, 255, fillAlpha),
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
              // ── Live Interactive Glass Preview ──
              _LiveGlassPreview(
                finish: resolvedFinish,
                finishPref: currentFinish,
                intensity: currentIntensity,
                blur: blur,
                isDark: isDark,
                scheme: scheme,
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Glass Finish Options ──
              AppGroupedSection(
                header: 'Liquid Glass Finish',
                children: [
                  _GlassFinishOptionTile(
                    title: 'Clear',
                    subtitle:
                        'Crystal-clear optical liquid glass with zero blur & pure refraction',
                    icon: Icons.water_drop_outlined,
                    badge: 'Recommended',
                    isSelected: currentFinish == AppGlassFinish.clear,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(ledgerProvider.notifier).updatePreferencesWith(
                            (live) => live.withGlassFinish(AppGlassFinish.clear),
                          );
                    },
                  ),
                  const GlassDivider(),
                  _GlassFinishOptionTile(
                    title: 'Regular',
                    subtitle:
                        'Apple Liquid Glass with calibrated blur & adaptive transmission',
                    icon: Icons.blur_linear_outlined,
                    badge: 'Apple Standard',
                    isSelected: currentFinish == AppGlassFinish.regular,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(ledgerProvider.notifier).updatePreferencesWith(
                            (live) =>
                                live.withGlassFinish(AppGlassFinish.regular),
                          );
                    },
                  ),
                  const GlassDivider(),
                  _GlassFinishOptionTile(
                    title: 'Frosted',
                    subtitle:
                        'Diffused frosted glass with heavy blur & velvety frost',
                    icon: Icons.blur_on_outlined,
                    badge: 'Heavy Blur',
                    isSelected: currentFinish == AppGlassFinish.frosted,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref.read(ledgerProvider.notifier).updatePreferencesWith(
                            (live) =>
                                live.withGlassFinish(AppGlassFinish.frosted),
                          );
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // ── Refraction Intensity / Blur Tuning ──
              AppGroupedSection(
                header: 'Optics Intensity',
                children: [
                  for (final intensity in GlassIntensity.values) ...[
                    if (intensity != GlassIntensity.values.first)
                      const GlassDivider(),
                    AppGroupedTile(
                      leading: Icon(
                        switch (intensity) {
                          GlassIntensity.light => Icons.looks_one_outlined,
                          GlassIntensity.medium => Icons.looks_two_outlined,
                          GlassIntensity.heavy => Icons.looks_3_outlined,
                        },
                      ),
                      title: Text(
                        switch (intensity) {
                          GlassIntensity.light => 'Light',
                          GlassIntensity.medium => 'Medium',
                          GlassIntensity.heavy => 'Heavy',
                        },
                      ),
                      subtitle: Text(
                        switch (intensity) {
                          GlassIntensity.light =>
                            'Subtle frosted surface with soft blur and low opacity',
                          GlassIntensity.medium =>
                            'Balanced liquid glass with standard blur and refraction',
                          GlassIntensity.heavy =>
                            'Strong frosted glass with deeper blur and opacity',
                        },
                      ),
                      trailing: currentIntensity == intensity
                          ? Icon(
                              Icons.check_circle_rounded,
                              color: scheme.primary,
                            )
                          : null,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref.read(ledgerProvider.notifier).updatePreferencesWith(
                              (live) => live.withGlassIntensity(intensity),
                            );
                      },
                    ),
                  ],
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

class _LiveGlassPreview extends StatelessWidget {
  const _LiveGlassPreview({
    required this.finish,
    required this.finishPref,
    required this.intensity,
    required this.blur,
    required this.isDark,
    required this.scheme,
  });

  final g1455.GlassFinish finish;
  final AppGlassFinish finishPref;
  final GlassIntensity intensity;
  final double blur;
  final bool isDark;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final fillAlphaTop = finishPref.backgroundOpacity(
      intensity: intensity,
      isDark: isDark,
    );
    final fillAlphaBottom = (fillAlphaTop * 0.45).clamp(0.01, 0.85);
    final borderAlpha = finishPref.borderOpacity(
      intensity: intensity,
      isDark: isDark,
    );

    return Container(
      height: 250,
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
          // ── Vivid Background Finance Scene with High-Contrast Elements ──
          Positioned.fill(
            child: ColoredBox(
              color: isDark ? const Color(0xFF0F1017) : const Color(0xFFE8E9F0),
              child: Stack(
                children: [
                  // Luminous colorful gradient background accents
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
                              'LIVE OPTICS PREVIEW',
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
                            color: Colors.white.withAlphaFactor(isDark ? 0.10 : 0.40),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.white.withAlphaFactor(isDark ? 0.20 : 0.60),
                            ),
                          ),
                          child: Text(
                            '${finishPref.label.toUpperCase()} · ${blur == 0 ? "0PX" : "${blur.toInt()}PX"}',
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

                  // ── High-Contrast Colorful Account Cards (Spans through and behind glass) ──
                  Positioned(
                    top: 42,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        // Card 1: Chase Blue
                        Expanded(
                          child: Container(
                            height: 110,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF1976D2),
                                  Color(0xFF0D47A1),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF1976D2).withAlphaFactor(0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Icon(Icons.credit_card, color: Colors.white, size: 16),
                                    Text(
                                      'USD',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                                Spacer(),
                                Text(
                                  'Chase Checking',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '\$1,460.00',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Card 2: HDFC Emerald (Crucial contrast card)
                        Expanded(
                          child: Container(
                            height: 110,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFF00C853),
                                  Color(0xFF007E33),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00C853).withAlphaFactor(0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Icon(Icons.account_balance, color: Colors.white, size: 16),
                                    Text(
                                      'INR',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                                Spacer(),
                                Text(
                                  'Salary Deposit',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '+₹7,37,808',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),

                        // Card 3: Coral Transit
                        Expanded(
                          child: Container(
                            height: 110,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: const LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Color(0xFFFF3D00),
                                  Color(0xFFDD2C00),
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFFF3D00).withAlphaFactor(0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Icon(Icons.directions_subway, color: Colors.white, size: 16),
                                    Text(
                                      'JPY',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                                Spacer(),
                                Text(
                                  'Suica IC',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white70,
                                  ),
                                ),
                                SizedBox(height: 2),
                                Text(
                                  '-¥96,700',
                                  style: TextStyle(
                                    fontSize: 14,
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

                  // ── Chart bars spanning across the middle ──
                  Positioned(
                    top: 140,
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
                              boxShadow: [
                                BoxShadow(
                                  color: bar.$1.withAlphaFactor(0.40),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── The Live Liquid Glass Surface Floating Over the Lower Half ──
          Positioned(
            left: 14,
            right: 14,
            bottom: 12,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: g1455.GlassSurface(
                  borderRadius: BorderRadius.circular(20),
                  finish: finish,
                  labelled: false,
                  child: Container(
                    height: 82,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withAlphaFactor(borderAlpha),
                        width: 1.2,
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white.withAlphaFactor(fillAlphaTop),
                          Colors.white.withAlphaFactor(fillAlphaBottom),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withAlphaFactor(isDark ? 0.35 : 0.15),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        // Status indicator pill
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
                            border: Border.all(
                              color: Colors.white.withAlphaFactor(0.50),
                              width: 1.2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: scheme.primary.withAlphaFactor(0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Icon(
                            switch (finishPref) {
                              AppGlassFinish.clear => Icons.water_drop_rounded,
                              AppGlassFinish.regular => Icons.blur_linear_rounded,
                              AppGlassFinish.frosted => Icons.blur_on_rounded,
                            },
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Title and real-time description
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
                                      fontSize: 16,
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
                                      border: Border.all(
                                        color: scheme.primary.withAlphaFactor(0.40),
                                      ),
                                    ),
                                    child: Text(
                                      blur == 0
                                          ? '0px Blur · Clear'
                                          : '${blur.toInt()}px Blur · ${intensity.name.toUpperCase()}',
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
                                    'Cards behind are 100% sharp & crystal clear',
                                  AppGlassFinish.regular =>
                                    'Cards behind smoothly soften into Apple sheen',
                                  AppGlassFinish.frosted =>
                                    'Cards behind deeply blur into velvety frost',
                                },
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
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
              ),
            ),
          ),
        ],
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
