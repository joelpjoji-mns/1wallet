import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_controller.dart';
import '../data/ledger_providers.dart';
import '../design/tokens.dart';
import '../ledger/ledger_selectors.dart';
import 'user_identity_widgets.dart';

/// Main navigation drawer matching the React Native AppDrawer.
///
/// Shows the user profile, account quick list, and navigation links
/// for all settings/feature sections.
class AppDrawerWidget extends ConsumerWidget {
  const AppDrawerWidget({super.key});

  static const _managementLinks = [
    (
      'Settings',
      'Preferences, theme, profile',
      Icons.settings_outlined,
      '/settings',
    ),
    ('Sync', 'Cloud backup and restore', Icons.cloud_sync_outlined, '/sync'),
    (
      'Currencies',
      'Base currency and exchange rates',
      Icons.currency_exchange_outlined,
      '/currencies',
    ),
    (
      'Categories',
      'Expense and income categories',
      Icons.category_outlined,
      '/categories',
    ),
    ('Widgets', 'Home dashboard layout', Icons.widgets_outlined, '/widgets'),
    ('Cards', 'Credit card tracking', Icons.credit_card_outlined, '/cards'),
    (
      'Loans & EMI',
      'Loan accounts and repayments',
      Icons.account_balance_outlined,
      '/loans',
    ),
    (
      'Recurring',
      'Bills, subscriptions, income',
      Icons.event_repeat_outlined,
      '/recurring',
    ),
    (
      'Import & backup',
      'CSV, SMS, archive',
      Icons.file_upload_outlined,
      '/imports',
    ),
    (
      'Notifications',
      'Alerts and reminders',
      Icons.notifications_outlined,
      '/notifications',
    ),
    (
      'Review queue',
      'Capture candidates',
      Icons.fact_check_outlined,
      '/review',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(ledgerProvider);
    final auth = ref.watch(authControllerProvider);
    final user = auth.user;
    final accounts = state.accounts
        .where((a) => !a.isArchived)
        .take(5)
        .toList();
    final total = totalBalance(state);

    return Drawer(
      backgroundColor: theme.colorScheme.surface,
      child: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.md,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withAlpha(60),
                border: Border(
                  bottom: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AuthUserAvatar(
                        user: user,
                        radius: 24,
                        fallbackLabel: user?.initials ?? '1W',
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? '1wallet',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              user?.email ?? 'Local session',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      AuthProviderChip(user: user, compact: true),
                      AuthPhotoStatusChip(user: user, compact: true),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  // Total balance
                  Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        'Total: ${formatMoney(total, state.preferences.locale)}',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Quick account list
            if (accounts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Column(
                  children: [
                    for (final account in accounts)
                      ListTile(
                        dense: true,
                        leading: Icon(
                          accountIcon(account),
                          size: 20,
                          color: account.color ?? theme.colorScheme.primary,
                        ),
                        title: Text(
                          account.name,
                          style: const TextStyle(fontSize: 13),
                        ),
                        trailing: Text(
                          formatMoney(
                            accountBalance(state, account),
                            state.preferences.locale,
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          context.push('/account/${account.id}');
                        },
                      ),
                    const Divider(),
                  ],
                ),
              ),

            // Navigation links
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                children: [
                  for (final link in _managementLinks)
                    ListTile(
                      dense: true,
                      leading: Icon(link.$3, size: 20),
                      title: Text(
                        link.$1,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        link.$2,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push(link.$4);
                      },
                    ),
                ],
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '1wallet Flutter · ${state.accounts.length} accounts · ${state.transactions.length} records',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
