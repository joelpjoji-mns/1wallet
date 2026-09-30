import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../common/route_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../utils/currency_utils.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/privacy_text.dart';

class CardsScreen extends ConsumerWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final cards = state.accounts
        .where(
          (account) =>
              !account.isArchived &&
              (account.type == 'credit_card' || account.type == 'card'),
        )
        .toList();
    return _AccountCollectionScreen(
      title: 'Cards',
      subtitle: 'Custom card definitions, color, icon and outstanding balance.',
      accounts: cards,
      emptyTitle: 'No cards yet',
      newAccountType: 'credit_card',
    );
  }
}

class _AccountCollectionScreen extends ConsumerWidget {
  const _AccountCollectionScreen({
    required this.title,
    required this.subtitle,
    required this.accounts,
    required this.emptyTitle,
    required this.newAccountType,
  });

  final String title;
  final String subtitle;
  final List<Account> accounts;
  final String emptyTitle;
  final String newAccountType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    return RouteScaffold(
      title: title,
      actions: [
        IconButton(
          onPressed: () => context.push('/account/new?type=$newAccountType'),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: Column(
        children: [
          SectionCard(
            title: title,
            subtitle: subtitle,
            child: MetricTile(
              label: 'Count',
              value: '${accounts.length}',
              icon: Icons.credit_card_outlined,
            ),
          ),
          const Gap(AppSpacing.lg),
          if (accounts.isEmpty)
            EmptyState(
              icon: Icons.credit_card_off_outlined,
              title: emptyTitle,
              body: 'Add one from Accounts to enable this screen.',
            )
          else
            for (final account in accounts) ...[
              _CardAccountTile(state: state, account: account),
              const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }
}

class _CardAccountTile extends ConsumerWidget {
  const _CardAccountTile({
    required this.state,
    required this.account,
  });

  final LedgerState state;
  final Account account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final dueStatus = creditCardDueStatus(state, account);
    final rawBalance = accountBalance(state, account);
    final displayBalance = convertMoneyForDisplay(state, rawBalance);

    Color badgeColor = scheme.surfaceContainerHighest;
    Color badgeTextColor = scheme.onSurfaceVariant;
    String badgeLabel = '';
    IconData badgeIcon = Icons.event_outlined;

    if (dueStatus != null) {
      if (dueStatus.isPaid) {
        badgeColor = Colors.green.withAlphaFactor(0.2);
        badgeTextColor = Colors.green;
        badgeLabel = 'Bill paid';
        badgeIcon = Icons.check_circle_outline_rounded;
      } else if (dueStatus.isOverdue) {
        badgeColor = scheme.error.withAlphaFactor(0.2);
        badgeTextColor = scheme.error;
        badgeLabel = dueStatus.daysUntilDue == -1
            ? 'Overdue yesterday'
            : 'Overdue (${-dueStatus.daysUntilDue}d ago)';
        badgeIcon = Icons.warning_amber_rounded;
      } else if (dueStatus.isDueSoon) {
        badgeColor = scheme.error.withAlphaFactor(0.2);
        badgeTextColor = scheme.error;
        badgeLabel = dueStatus.daysUntilDue == 0
            ? 'Due today'
            : (dueStatus.daysUntilDue == 1
                ? 'Due tomorrow'
                : 'Due in ${dueStatus.daysUntilDue} days');
        badgeIcon = Icons.alarm_rounded;
      } else if (dueStatus.isStatementGenerated) {
        badgeColor = scheme.primary.withAlphaFactor(0.18);
        badgeTextColor = scheme.primary;
        badgeLabel = 'Bill ready · Due in ${dueStatus.daysUntilDue}d';
        badgeIcon = Icons.receipt_long_rounded;
      } else {
        badgeColor = scheme.surfaceContainerHighest;
        badgeTextColor = scheme.onSurfaceVariant;
        badgeLabel = 'Due ${DateFormat('d MMM').format(dueStatus.dueDate)}';
        badgeIcon = Icons.event_outlined;
      }
    }

    final subtitleParts = [
      account.institution,
      if (account.displayLast4 != null) '•••• ${account.displayLast4}',
      account.currency,
      if (dueStatus?.statementDate != null)
        'Bill: ${DateFormat('d MMM').format(dueStatus!.statementDate!)}',
    ].whereType<String>().join(' · ');

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: dueStatus != null && (dueStatus.isDueSoon || dueStatus.isOverdue)
              ? scheme.error.withAlphaFactor(0.5)
              : scheme.outlineVariant.withAlphaFactor(0.4),
          width: dueStatus != null && (dueStatus.isDueSoon || dueStatus.isOverdue)
              ? 1.5
              : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => context.push('/account/${account.id}'),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: (account.color ?? scheme.primary).withAlphaFactor(0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        accountIcon(account),
                        size: 20,
                        color: account.color ?? scheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitleParts.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              subtitleParts,
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    PrivacyText(
                      formatMoney(displayBalance, state.preferences.locale),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
                if (dueStatus != null) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(badgeIcon, size: 14, color: badgeTextColor),
                            const SizedBox(width: 5),
                            Text(
                              badgeLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: badgeTextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      if (!dueStatus.isPaid)
                        TextButton.icon(
                          onPressed: () {
                            ref
                                .read(ledgerProvider.notifier)
                                .markCardBillPaid(account.id, dueStatus.cycleKey);
                          },
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text('Confirm Paid', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          ),
                        )
                      else
                        TextButton(
                          onPressed: () {
                            ref
                                .read(ledgerProvider.notifier)
                                .markCardBillPaid(account.id, null);
                          },
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          ),
                          child: Text(
                            'Unmark Paid',
                            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
