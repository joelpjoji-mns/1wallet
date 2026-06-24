import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';

class TransactionDetailScreen extends ConsumerStatefulWidget {
  const TransactionDetailScreen({required this.transactionId, super.key});

  final String transactionId;

  @override
  ConsumerState<TransactionDetailScreen> createState() =>
      _TransactionDetailScreenState();
}

class _TransactionDetailScreenState
    extends ConsumerState<TransactionDetailScreen> {
  bool _isAttaching = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final transaction = state.transactions.firstWhereOrNull(
      (record) => record.id == widget.transactionId,
    );
    if (transaction == null) {
      return RouteScaffold(
        title: 'Transaction detail',
        child: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'Record not found',
          body:
              'The selected transaction is not available in your wallet data.',
          actionLabel: 'Back home',
          onAction: () => context.go('/'),
        ),
      );
    }
    final account = accountById(state, transaction.accountId);
    final counterAccount = accountById(state, transaction.counterAccountId);
    final category = categoryById(state, transaction.categoryId);
    final signedAmount = incomeTypes.contains(transaction.type)
        ? transaction.amount.amountMinor
        : -transaction.amount.amountMinor.abs();
    final secondaryAmounts = _secondaryAmountLines(state, transaction);
    return RouteScaffold(
      title: 'Transaction detail',
      actions: [
        IconButton(
          onPressed: () => context.push('/add?transactionId=${transaction.id}'),
          icon: const Icon(Icons.edit_outlined),
        ),
        IconButton(
          onPressed: () => _confirmDelete(context, ref, transaction),
          icon: const Icon(Icons.delete_outline_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Premium Hero Section
          GestureDetector(
            onTap: () =>
                context.push('/add?transactionId=${transaction.id}&tab=0'),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    (category?.color ?? Theme.of(context).colorScheme.primary)
                        .withAlphaFactor(0.2),
                    Theme.of(context).colorScheme.surface,
                  ],
                ),
                borderRadius: BorderRadius.circular(AppRadii.xl),
                border: Border.all(
                  color:
                      (category?.color ?? Theme.of(context).colorScheme.primary)
                          .withAlphaFactor(0.3),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    category?.name ?? transactionTypeLabel(transaction.type),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    formatMoney(
                      transaction.amount.copyWith(amountMinor: signedAmount),
                      state.preferences.locale,
                    ),
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: amountColor(context, signedAmount),
                    ),
                  ),
                  for (final amountLine in secondaryAmounts)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        amountLine,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.lg),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withAlphaFactor(0.5),
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      formatLedgerDate(
                        transaction.occurredAt,
                        state.preferences.locale,
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (transaction.locationLabel != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.place_outlined, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          transaction.locationLabel!,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Movement',
            child: Column(
              children: [
                PremiumRow(
                  icon: account == null
                      ? Icons.wallet_outlined
                      : accountIcon(account),
                  title: account?.name ?? 'Missing account',
                  subtitle: account == null
                      ? null
                      : accountTypeLabel(account.type),
                  meta: account == null
                      ? null
                      : formatMoney(
                          accountBalance(state, account),
                          state.preferences.locale,
                        ),
                  iconColor: account?.color,
                  onTap: () => context.push(
                    '/add?transactionId=${transaction.id}&tab=0',
                  ),
                ),
                if (counterAccount != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  PremiumRow(
                    icon: accountIcon(counterAccount),
                    title: counterAccount.name,
                    subtitle: 'Counter account',
                    meta: formatMoney(
                      accountBalance(state, counterAccount),
                      state.preferences.locale,
                    ),
                    iconColor: counterAccount.color,
                    onTap: () => context.push(
                      '/add?transactionId=${transaction.id}&tab=0',
                    ),
                  ),
                ],
                if (category != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  PremiumRow(
                    icon: categoryIcon(category),
                    title: category.name,
                    subtitle: categoryPath(state, category),
                    iconColor: category.color,
                    onTap: () => context.push(
                      '/add?transactionId=${transaction.id}&tab=0',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Details',
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => context.push(
                    '/add?transactionId=${transaction.id}&tab=1',
                  ),
                  behavior: HitTestBehavior.opaque,
                  child: InfoRow(
                    label: 'Date',
                    value: formatLedgerDate(
                      transaction.occurredAt,
                      state.preferences.locale,
                    ),
                    icon: Icons.calendar_month_outlined,
                  ),
                ),
                GestureDetector(
                  onTap: () => context.push(
                    '/add?transactionId=${transaction.id}&tab=1',
                  ),
                  behavior: HitTestBehavior.opaque,
                  child: InfoRow(
                    label: 'Time',
                    value: DateFormat.jm(
                      state.preferences.locale.replaceAll('_', '-'),
                    ).format(transaction.occurredAt),
                    icon: Icons.schedule_outlined,
                  ),
                ),
                if (transaction.originalFxRate != null)
                  InfoRow(
                    label: 'Original FX rate',
                    value: transaction.originalFxRate!.toStringAsFixed(6),
                    icon: Icons.currency_exchange_outlined,
                  ),
                if (transaction.fxRate != null)
                  InfoRow(
                    label: 'FX rate',
                    value: transaction.fxRate!.toStringAsFixed(6),
                    icon: Icons.currency_exchange_outlined,
                  ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Notes',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => context.push(
                    '/add?transactionId=${transaction.id}&tab=1',
                  ),
                  behavior: HitTestBehavior.opaque,
                  child: Text(
                    transaction.notes ?? 'No notes added.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Receipts',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _isAttaching
                          ? null
                          : () =>
                                _attachReceipt(transaction, ImageSource.camera),
                      icon: _isAttaching
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.camera_alt_outlined),
                      label: const Text('Scan'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isAttaching
                          ? null
                          : () => _attachReceipt(
                              transaction,
                              ImageSource.gallery,
                            ),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Photo'),
                    ),
                  ],
                ),
                if (transaction.attachments.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  for (final attachment in transaction.attachments) ...[
                    InfoRow(
                      icon: Icons.attach_file_outlined,
                      label: attachment.source,
                      value: attachment.name,
                    ),
                    if (attachment != transaction.attachments.last)
                      const Divider(height: AppSpacing.md),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _attachReceipt(
    TransactionRecord transaction,
    ImageSource source,
  ) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source);
    if (file == null) return;

    setState(() => _isAttaching = true);
    try {
      final attachment = TransactionAttachment(
        id: 'att-${DateTime.now().millisecondsSinceEpoch}',
        source: source == ImageSource.camera ? 'camera' : 'library',
        name: file.name,
        uri: file.path,
      );
      await ref
          .read(ledgerProvider.notifier)
          .addAttachment(transaction.id, attachment);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Receipt attached'),
            behavior: SnackBarBehavior.floating,
          ),
        );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isAttaching = false);
    }
  }

  List<String> _secondaryAmountLines(
    LedgerState state,
    TransactionRecord transaction,
  ) {
    final lines = <String>[];
    if (transaction.originalAmount != null &&
        !_sameMoney(transaction.originalAmount!, transaction.amount)) {
      lines.add(
        'Original ${formatMoney(transaction.originalAmount!, state.preferences.locale)}',
      );
    }
    if (transaction.counterAmount != null &&
        !_sameMoney(transaction.counterAmount!, transaction.amount)) {
      lines.add(
        'Counter ${formatMoney(transaction.counterAmount!, state.preferences.locale)}',
      );
    }
    if (!_sameMoney(transaction.baseAmount, transaction.amount)) {
      lines.add(
        'Base ${formatMoney(transaction.baseAmount, state.preferences.locale)}',
      );
    }
    return lines;
  }

  bool _sameMoney(Money left, Money right) {
    return left.amountMinor == right.amountMinor &&
        left.currency == right.currency;
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    TransactionRecord transaction,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete record?'),
        content: const Text(
          'This removes the record from your local Flutter ledger.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(ledgerProvider.notifier).deleteTransaction(transaction.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Record deleted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    context.go('/');
  }
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}
