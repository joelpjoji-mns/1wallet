import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppGlassPage extends StatelessWidget {
  const AppGlassPage({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: DecoratedBox(
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
        child: child,
      ),
    );
  }
}
