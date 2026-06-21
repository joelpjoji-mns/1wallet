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
          DailySpendingLimitWidget(state: state),
          const Gap(AppSpacing.lg),
          UpcomingPlannedBillsWidget(state: state),
          const Gap(AppSpacing.lg),
          UpcomingIncomeWidget(state: state),
          const Gap(AppSpacing.lg),
          BudgetHealth503020Widget(state: state),
          const Gap(AppSpacing.lg),
          EmergencyFundHealthWidget(state: state),
          const Gap(AppSpacing.lg),
          DebtFreeTargetWidget(state: state),
          const Gap(AppSpacing.lg),
          ActiveSavingsGoalsWidget(state: state),
          const Gap(AppSpacing.lg),
          SubscriptionsWatchWidget(state: state),
          const Gap(AppSpacing.lg),
          Cashflow30DayPredictorWidget(state: state),
          const Gap(AppSpacing.lg),
          HighInterestAlertWidget(state: state),
          const Gap(AppSpacing.lg),
          PlannedVsActualWidget(state: state),
          const Gap(AppSpacing.lg),
          TaxBufferPredictorWidget(state: state),
          const Gap(AppSpacing.lg),
          InvestmentTargetWidget(state: state),
          const Gap(AppSpacing.lg),
          AnnualSinkingFundsWidget(state: state),
          const Gap(AppSpacing.lg),
          NetWorthPredictorWidget(state: state),
          const Gap(AppSpacing.xxl),
        ],
      ),
    );
  }
}
