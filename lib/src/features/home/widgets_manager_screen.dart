import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../common/full_screen_picker.dart';
import '../common/route_scaffold.dart';
import 'home_widget_models.dart';

class WidgetsManagerScreen extends ConsumerWidget {
  const WidgetsManagerScreen({super.key});

  static const _reportWidgetIds = {
    'balanceHero',
    'cashflowBook',
    'topCategories',
    'incomeMix',
    'budgetPressure',
    'goalProgress',
    'accountGroups',
  };

  static const widgets = [
    _WidgetCatalogItem(
      'balanceHero',
      'Balance hero',
      'Current balance with period income and expense.',
      Icons.account_balance_wallet_outlined,
      'wide',
    ),
    _WidgetCatalogItem(
      'accountGrid',
      'All accounts',
      'Compact account tiles with balances and status badges.',
      Icons.view_comfy_alt_outlined,
      'wide',
    ),
    _WidgetCatalogItem(
      'summaryTiles',
      'Finance summary',
      'Planned payments, debt, and net worth summary tiles.',
      Icons.dashboard_customize_outlined,
      'medium',
    ),
    _WidgetCatalogItem(
      'recentRecords',
      'Recent records',
      'Latest cleared transactions from the ledger.',
      Icons.format_list_bulleted_rounded,
      'wide',
    ),
    _WidgetCatalogItem(
      'upcomingScheduled',
      'Upcoming planned',
      'Scheduled records and subscriptions sorted by due date.',
      Icons.calendar_month_outlined,
      'wide',
    ),
    _WidgetCatalogItem(
      'dueNow',
      'Due now',
      'Bills, EMIs, and card payments due today or overdue.',
      Icons.calendar_today_outlined,
      'medium',
    ),
    _WidgetCatalogItem(
      'emiTracker',
      'EMI tracker',
      'Loan repayment timeline, next EMI, and planned EMI total.',
      Icons.account_balance_outlined,
      'medium',
    ),
    _WidgetCatalogItem(
      'cardDebt',
      'Card debt',
      'Credit card exposure and highest outstanding card.',
      Icons.credit_card_outlined,
      'medium',
    ),
    _WidgetCatalogItem(
      'accountGroups',
      'Account groups',
      'Balances grouped by bank, wallet, card, forex, and archive rows.',
      Icons.folder_copy_outlined,
      'wide',
    ),
    _WidgetCatalogItem(
      'reviewQueue',
      'Review queue',
      'Pending capture candidates and source breakdown.',
      Icons.smart_toy_outlined,
      'medium',
    ),
    _WidgetCatalogItem(
      'automationHealth',
      'Automation health',
      'Review queue, import warnings, scheduled work, and parser readiness.',
      Icons.shield_outlined,
      'medium',
    ),
    _WidgetCatalogItem(
      'cashflowForecast',
      '30-day forecast',
      'Upcoming scheduled income, bills, EMIs, cards, and transfers.',
      Icons.timeline_outlined,
      'wide',
    ),
    _WidgetCatalogItem(
      'billWatch',
      'Bills watch',
      'Subscriptions, utilities, card dues, and auto-debit bills coming up.',
      Icons.assignment_outlined,
      'medium',
    ),
    _WidgetCatalogItem(
      'cardPaymentPlan',
      'Card payment plan',
      'Scheduled card payments and card debt readiness.',
      Icons.credit_score_outlined,
      'medium',
    ),
    _WidgetCatalogItem(
      'loanPayoff',
      'Loan payoff',
      'Loan balances, upcoming EMIs, and monthly repayment pressure.',
      Icons.account_balance_wallet_outlined,
      'medium',
    ),
    _WidgetCatalogItem(
      'savingsRunway',
      'Savings runway',
      'Liquid balance compared with the last 30 days of spending.',
      Icons.hourglass_bottom_outlined,
      'medium',
    ),
    _WidgetCatalogItem(
      'cashflowBook',
      'Cashflow book',
      'Current period income, expenses, net, and dates.',
      Icons.menu_book_outlined,
      'medium',
    ),
    _WidgetCatalogItem(
      'balanceTrend',
      'Balance trend',
      'Running balance line chart for the selected period.',
      Icons.bar_chart_outlined,
      'wide',
    ),
    _WidgetCatalogItem(
      'topCategories',
      'Top categories',
      'Top spending categories for the current period.',
      Icons.category_outlined,
      'wide',
    ),
    _WidgetCatalogItem(
      'incomeMix',
      'Income mix',
      'Income grouped by category, salary, refunds, interest, and cashback.',
      Icons.donut_large_outlined,
      'wide',
    ),
    _WidgetCatalogItem(
      'currencyValues',
      'Currency values',
      'Exchange-rate trend and quick converter.',
      Icons.currency_exchange_outlined,
      'wide',
    ),
    _WidgetCatalogItem(
      'budgetPressure',
      'Budget pressure',
      'Budget utilization and overrun warnings.',
      Icons.speed_outlined,
      'wide',
    ),
    _WidgetCatalogItem(
      'goalProgress',
      'Goal progress',
      'Goal progress and required monthly pace.',
      Icons.track_changes_outlined,
      'wide',
    ),
    _WidgetCatalogItem(
      'currencyExposure',
      'Currency exposure',
      'Non-base currency balances like forex cards.',
      Icons.monetization_on_outlined,
      'medium',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final theme = Theme.of(context);
    final visibleOrder = resolveHomeWidgetOrder(
      state.preferences.homeWidgetOrder,
      hidden: state.preferences.homeWidgetHidden,
    ).map((item) => item.storageKey).toList();
    final reports = widgets
        .where((widget) => _reportWidgetIds.contains(widget.id))
        .toList();
    final dashboard = widgets
        .where((widget) => !_reportWidgetIds.contains(widget.id))
        .toList();

    return RouteScaffold(
      title: 'Widgets',
      actions: [
        IconButton(
          tooltip: 'Home',
          icon: const Icon(Icons.home_outlined),
          onPressed: () => context.go('/'),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadii.lg),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${visibleOrder.length} on Home',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${widgets.length - visibleOrder.length} available to add',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    ref.read(ledgerProvider.notifier).resetHomeWidgetOrder();
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        const SnackBar(
                          content: Text('Home widgets reset'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                  },
                  icon: const Icon(Icons.restart_alt_rounded),
                  label: const Text('Reset'),
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          _WidgetGroup(
            title: 'Reports',
            items: reports,
            visibleOrder: visibleOrder,
            preferences: state.preferences,
          ),
          const Gap(AppSpacing.lg),
          _WidgetGroup(
            title: 'Dashboard',
            items: dashboard,
            visibleOrder: visibleOrder,
            preferences: state.preferences,
          ),
        ],
      ),
    );
  }
}

class _WidgetGroup extends StatelessWidget {
  const _WidgetGroup({
    required this.title,
    required this.items,
    required this.visibleOrder,
    required this.preferences,
  });

  final String title;
  final List<_WidgetCatalogItem> items;
  final List<String> visibleOrder;
  final LedgerPreferences preferences;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Column(
          children: [
            for (final item in items) ...[
              _WidgetTile(
                item: item,
                isVisible: visibleOrder.contains(item.id),
                size: preferences.homeWidgetSizes[item.id] ?? item.size,
                datePreset:
                    preferences.homeWidgetFilters[item.id] ??
                    defaultDatePresetForHomeWidget(item.id),
              ),
              if (item != items.last) const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ],
    );
  }
}

class _WidgetTile extends ConsumerWidget {
  const _WidgetTile({
    required this.item,
    required this.isVisible,
    required this.size,
    required this.datePreset,
  });

  final _WidgetCatalogItem item;
  final bool isVisible;
  final String size;
  final String datePreset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Card(
      elevation: isVisible ? 1 : 0,
      margin: EdgeInsets.zero,
      color: isVisible
          ? theme.colorScheme.surfaceContainer
          : theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(
          color: isVisible
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        onTap: () {
          if (isVisible) {
            context.go('/');
          } else {
            _restoreWidget(context, ref);
          }
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            58,
            AppSpacing.md,
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: isVisible
                          ? theme.colorScheme.primaryContainer
                          : theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      item.icon,
                      color: isVisible
                          ? theme.colorScheme.onPrimaryContainer
                          : theme.colorScheme.onSecondaryContainer,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                          maxLines: 1,
                        ),
                        Text(
                          item.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 3,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          runSpacing: AppSpacing.xs,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            _MetaChip(isVisible ? 'On Home' : 'Hidden'),
                            _MetaChip(_sizeLabel(size)),
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              avatar: const Icon(
                                Icons.calendar_month,
                                size: 16,
                              ),
                              label: Text(homeWidgetDateLabel(datePreset)),
                              onPressed: () => _chooseDatePreset(context, ref),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Positioned(
                top: -8,
                right: -50,
                child: IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: isVisible
                        ? theme.colorScheme.primaryContainer
                        : theme.colorScheme.secondaryContainer,
                    foregroundColor: isVisible
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.onSecondaryContainer,
                  ),
                  iconSize: 17,
                  icon: Icon(
                    isVisible ? Icons.check_rounded : Icons.add_rounded,
                  ),
                  onPressed: () {
                    if (isVisible) {
                      context.go('/');
                    } else {
                      _restoreWidget(context, ref);
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseDatePreset(BuildContext context, WidgetRef ref) async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: '${item.title} period',
      searchable: false,
      selectedValue: datePreset,
      options: [
        for (final preset in allowedDatePresetsForHomeWidget(item.id))
          PickerOption(
            value: preset,
            title: homeWidgetDateLabel(preset),
            icon: Icons.calendar_month_outlined,
          ),
      ],
    );
    if (next == null) return;
    await ref.read(ledgerProvider.notifier).setHomeWidgetFilter(item.id, next);
  }

  void _restoreWidget(BuildContext context, WidgetRef ref) {
    final state = ref.read(ledgerProvider);
    final order = restoreHomeWidgetStorageKey(
      state.preferences.homeWidgetOrder,
      item.id,
    );
    final hidden = state.preferences.homeWidgetHidden
        .where((value) => value != item.id)
        .toList();
    ref
        .read(ledgerProvider.notifier)
        .setHomeWidgetPreferences(order: order, hidden: hidden);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('${item.title} added to Home'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text(label),
      labelStyle: Theme.of(context).textTheme.labelSmall,
    );
  }
}

class _WidgetCatalogItem {
  const _WidgetCatalogItem(
    this.id,
    this.title,
    this.subtitle,
    this.icon,
    this.size,
  );

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final String size;
}

String _sizeLabel(String value) {
  return switch (value) {
    'compact' => 'Compact',
    'medium' => 'Medium',
    'wide' => 'Wide',
    _ => value,
  };
}
