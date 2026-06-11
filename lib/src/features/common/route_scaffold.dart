import 'package:flutter/material.dart';
import '../../design/tokens.dart';

class RouteScaffold extends StatelessWidget {
  const RouteScaffold({
    required this.title,
    required this.child,
    super.key,
    this.actions = const [],
    this.floatingActionButton,
  });

  final String title;
  final Widget child;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
