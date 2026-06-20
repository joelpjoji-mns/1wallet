import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import 'planner_widgets.dart';

class PlannerScreen extends ConsumerWidget {
  const PlannerScreen({required this.onMenuPressed, super.key});
  final VoidCallback onMenuPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);

    return AppScreen(
      title: 'Statistics',
      onMenuPressed: onMenuPressed,
      child: Column(
        children: [
          BalanceTrendWidget(state: state),
          const Gap(AppSpacing.lg),
          TopCategoriesWidget(state: state),
          const Gap(AppSpacing.lg),
          CreditUtilizationWidget(state: state),
          const Gap(AppSpacing.xxl),
        ],
      ),
    );
  }
}
