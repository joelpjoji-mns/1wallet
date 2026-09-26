import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../main/main_shell.dart';

class DrawerConfig extends InheritedWidget {
  const DrawerConfig({required super.child, this.hasDrawer = false, super.key});

  final bool hasDrawer;

  static DrawerConfig? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<DrawerConfig>();
  }

  @override
  bool updateShouldNotify(DrawerConfig oldWidget) =>
      hasDrawer != oldWidget.hasDrawer;
}

class RouteScaffold extends StatelessWidget {
  const RouteScaffold({
    required this.title,
    this.child,
    this.scrollView,
    super.key,
    this.actions = const [],
    this.floatingActionButton,
    this.drawer,
    this.hasDrawer = false,
  }) : assert(
         (child == null) != (scrollView == null),
         'Provide exactly one of child or scrollView.',
       );

  final String title;

  /// Content laid out inside the default padded [ListView]. Mutually
  /// exclusive with [scrollView].
  final Widget? child;

  /// A pre-built scrollable (e.g. a [CustomScrollView] with slivers) used
  /// directly as the scaffold body content in place of the default
  /// [ListView]-wrapped [child]. Use this when a screen needs lazy/sliver
  /// building (for example many live widget previews) instead of eagerly
  /// building everything inside a single [Column]. Mutually exclusive with
  /// [child]. The caller owns any internal padding/sliver headers — this
  /// widget only supplies the shared [SafeArea] + centered max-width wrapper.
  final Widget? scrollView;

  final List<Widget> actions;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final bool hasDrawer;

  @override
  Widget build(BuildContext context) {
    final configHasDrawer = DrawerConfig.of(context)?.hasDrawer ?? false;
    final shouldShowDrawer = hasDrawer || configHasDrawer;

    final effectiveDrawer =
        drawer ??
        (shouldShowDrawer
            ? AppMainDrawer(
                selectedIndex: -1,
                onTabSelected: (index) {
                  // We might already be popped if we use GoRouter, but pop just in case there's a drawer open
                  if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
                    Navigator.of(context).pop();
                  }
                  // We must go back to the main shell and switch tabs
                  context.go('/');
                  // The tab selection is handled by MainShell when it mounts, but AppMainDrawer
                  // doesn't have a way to force MainShell's state from here easily unless we pass a param.
                  // For now, context.go('/') takes them home.
                },
              )
            : null);

    final content =
        scrollView ??
        ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.xxl,
          ),
          children: [child!],
        );

    Widget body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: content,
        ),
      ),
    );

    Widget mobileView = Scaffold(
      drawer: effectiveDrawer,
      drawerEnableOpenDragGesture: effectiveDrawer != null,
      appBar: GlassAppBar(
        title: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        leading: effectiveDrawer != null
            ? Builder(
                builder: (scaffoldContext) => AppMenuAction(
                  onPressed: Scaffold.of(scaffoldContext).openDrawer,
                ),
              )
            : Navigator.of(context).canPop()
            ? const AppBackAction()
            : null,
        actions: actions,
        centerTitle: false,
      ),
      floatingActionButton: floatingActionButton,
      body: body,
    );

    Widget desktopView = Scaffold(
      appBar: GlassAppBar(
        title: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        actions: actions,
        // Hide the hamburger menu button on desktop since the drawer is
        // persistent, but GlassAppBar (unlike Material's AppBar) has no
        // built-in Navigator awareness, so the back button still needs to
        // be supplied explicitly whenever there's no persistent drawer and
        // the route can actually be popped - otherwise every pushed desktop
        // sub-route would silently lose its way back.
        leading: effectiveDrawer != null
            ? const SizedBox.shrink()
            : (Navigator.of(context).canPop() ? const AppBackAction() : null),
        centerTitle: false,
      ),
      floatingActionButton: floatingActionButton,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (effectiveDrawer != null)
            drawer ??
                AppMainDrawer(
                  selectedIndex: -1,
                  isStatic: true,
                  onTabSelected: (index) {
                    context.go('/');
                  },
                ),
          Expanded(child: body),
        ],
      ),
    );

    return AppResponsiveLayout(mobile: mobileView, desktop: desktopView);
  }
}
