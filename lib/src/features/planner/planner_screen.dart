import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import 'planner_widgets_extended.dart';
import 'planner_widgets_extended_2.dart';
import 'planner_widgets_extended_3.dart';

class PlannerScreen extends ConsumerWidget {
  const PlannerScreen({required this.onMenuPressed, super.key});
  final VoidCallback onMenuPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);

    return AppScreen(
      title: 'Planner',
      onMenuPressed: onMenuPressed,
      child: Column(
        children: [
          const SizedBox(height: 12),
          DailySpendingLimitWidget(state: state),
          const SizedBox(height: 12),
          BudgetHealth503020Widget(state: state),
          const SizedBox(height: 12),
          EmergencyFundHealthWidget(state: state),
          const SizedBox(height: 12),
          DebtFreeTargetWidget(state: state),
          const SizedBox(height: 12),
          ActiveSavingsGoalsWidget(state: state),
          const SizedBox(height: 12),
          SubscriptionsWatchWidget(state: state),
          const SizedBox(height: 12),
          CashflowPredictorWidget(state: state),
          const SizedBox(height: 12),
          HighInterestAlertWidget(state: state),
          const SizedBox(height: 120),
        ],
      ),
    );
  }
}
