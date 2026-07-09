import 'package:flutter/material.dart';
import '../common/route_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/privacy_text.dart';

class CardsScreen extends ConsumerWidget {
  const CardsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    final cards = state.accounts
        .where((account) => account.type == 'credit_card')
        .toList();
    return _AccountCollectionScreen(
      title: 'Cards',
      subtitle: 'Custom card definitions, color, icon and outstanding balance.',
      accounts: cards,
      emptyTitle: 'No cards yet',
    );
  }
}

class _AccountCollectionScreen extends ConsumerWidget {
  const _AccountCollectionScreen({
    required this.title,
    required this.subtitle,
    required this.accounts,
    required this.emptyTitle,
  });

  final String title;
  final String subtitle;
  final List<Account> accounts;
  final String emptyTitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(ledgerProvider);
    return RouteScaffold(
      title: title,
      actions: [
        IconButton(
          onPressed: () => context.push('/account/new'),
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
              PremiumRow(
                icon: accountIcon(account),
                title: account.name,
                subtitle: [
                  account.institution,
                  account.groupName,
                  account.currency,
                ].whereType<String>().join(' · '),
                meta: maskMoneyIfPrivate(
                  state,
                  formatMoney(
                    convertMoneyForDisplay(
                      state,
                      accountBalance(state, account),
                    ),
                    state.preferences.locale,
                  ),
                ),
                iconColor: account.color,
                onTap: () => context.push('/account/${account.id}'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
        ],
      ),
    );
  }
}
