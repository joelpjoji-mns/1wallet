import 'package:flutter/material.dart';
import '../../design/tokens.dart';
import '../main/main_shell.dart';
import 'package:go_router/go_router.dart';

import 'package:go_router/go_router.dart';

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
    required this.child,
    super.key,
    this.actions = const [],
    this.floatingActionButton,
    this.drawer,
    this.hasDrawer = false,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final Widget? drawer;
  final bool hasDrawer;

  @override
  Widget build(BuildContext context) {
    final configHasDrawer = DrawerConfig.of(context)?.hasDrawer ?? false;
    final shouldShowDrawer = hasDrawer || configHasDrawer;

    final effectiveDrawer = drawer ??
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

    final isDesktop = AppResponsiveLayout.isDesktop(context);

    Widget body = SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: [child],
          ),
        ),
      ),
    );

    Widget mobileView = Scaffold(
      drawer: effectiveDrawer,
      drawerEnableOpenDragGesture: effectiveDrawer != null,
      appBar: AppBar(title: Text(title), actions: actions),
      floatingActionButton: floatingActionButton,
      body: body,
    );

    Widget desktopView = Scaffold(
      appBar: AppBar(
        title: Text(title), 
        actions: actions,
        // Hide the hamburger menu button on desktop since the drawer is persistent
        leading: effectiveDrawer != null ? const SizedBox.shrink() : null,
      ),
      floatingActionButton: floatingActionButton,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (effectiveDrawer != null)
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

    return AppResponsiveLayout(
      mobile: mobileView,
      desktop: desktopView,
    );
  }
}
