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

    final widgets = [
      DailySpendingLimitWidget(state: state),
      BudgetHealth503020Widget(state: state),
      EmergencyFundHealthWidget(state: state),
      DebtFreeTargetWidget(state: state),
      ActiveSavingsGoalsWidget(state: state),
      SubscriptionsWatchWidget(state: state),
      CashflowPredictorWidget(state: state),
      HighInterestAlertWidget(state: state),
      NetWorthSnapshotWidget(state: state),
      SavingsRateTrendWidget(state: state),
      BudgetHealthOverviewWidget(state: state),
    ];

    Widget mobileView = Column(
      children: [
        const SizedBox(height: 12),
        ...widgets.map((w) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: w,
        )),
        const SizedBox(height: 120),
      ],
    );

    Widget desktopView = SingleChildScrollView(
      padding: const EdgeInsets.only(top: 12, bottom: 120),
      child: Center(
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: widgets.map((w) => SizedBox(width: 450, child: w)).toList(),
        ),
      ),
    );

    return AppScreen(
      maxWidth: 1400,
      title: 'Planner',
      onMenuPressed: onMenuPressed,
      child: AppResponsiveLayout(
        mobile: mobileView,
        desktop: desktopView,
      ),
    );
  }
}
