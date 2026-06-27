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
                  Navigator.of(context).pop();
                  context.go('/');
                },
              )
            : null);

    return Scaffold(
      drawer: effectiveDrawer,
      drawerEnableOpenDragGesture: effectiveDrawer != null,
      appBar: AppBar(title: Text(title), actions: actions),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
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
    );
  }
}
