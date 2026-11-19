import 'package:flutter/material.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

class AppGlassPage extends StatelessWidget {
  const AppGlassPage({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return GlassPage(
      settings: isDark
          ? null
          : const LiquidGlassSettings(
              bodyMode: GlassBodyMode.clear,
              glassColor: Color(0x08FFFFFF),
              thickness: 8,
              blur: 8,
              visibility: 1.0,
              lightIntensity: 0.04,
              fresnelStrength: 0.04,
            ),
      background: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.scaffoldBackgroundColor,
              scheme.surfaceContainerLowest,
              theme.scaffoldBackgroundColor,
            ],
          ),
        ),
      ),
      statusBarStyle: theme.brightness == Brightness.dark
          ? GlassStatusBarStyle.light
          : GlassStatusBarStyle.dark,
      child: child,
    );
  }
}
