import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import '../common/route_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../common/category_hierarchy_picker.dart';
import '../common/full_screen_picker.dart';
import '../../utils/number_formatter.dart';

class CaptureDetailScreen extends ConsumerStatefulWidget {
  const CaptureDetailScreen({required this.candidateId, super.key});

  final String candidateId;

  @override
  ConsumerState<CaptureDetailScreen> createState() =>
      _CaptureDetailScreenState();
}

class _CaptureDetailScreenState extends ConsumerState<CaptureDetailScreen> {
  final _amountController = TextEditingController();
  final _merchantController = TextEditingController();
  String? _loadedCandidateId;
  var _type = 'expense';
  String? _accountId;
  String? _categoryId;

  @override
  void dispose() {
    _amountController.dispose();
    _merchantController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final candidate = state.captureCandidates.firstWhereOrNull(
      (candidate) => candidate.id == widget.candidateId,
    );
    if (candidate == null) {
      return RouteScaffold(
        title: 'Capture detail',
        child: EmptyState(
          icon: Icons.document_scanner_outlined,
          title: 'Candidate not found',
          body: 'This capture candidate is not available in the local ledger.',
          actionLabel: 'Back to review',
          onAction: () => context.push('/review'),
        ),
      );
    }
    _syncDraft(candidate, state);
    final selectedAccount = accountById(state, _accountId);
    final selectedCategory = categoryById(state, _categoryId);
    return RouteScaffold(
      title: 'Capture detail',
      actions: [
        IconButton(
          tooltip: 'Save draft',
          onPressed: () => _saveDraft(candidate, state),
          icon: const Icon(Icons.save_outlined),
        ),
      ],
      child: Column(
        children: [
          SectionCard(
            title: '${candidate.source.toUpperCase()} candidate',
            subtitle: DateFormat.yMMMMEEEEd(
              state.preferences.locale.replaceAll('_', '-'),
            ).add_jm().format(candidate.createdAt),
            child: Column(
              children: [
                InfoRow(
                  label: 'Status',
                  value: candidate.status,
                  icon: Icons.hourglass_top_outlined,
                  tone: candidate.status == 'pending'
                      ? MetricTone.warning
                      : MetricTone.standard,
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Parsed fields',
            subtitle: 'Edit these before confirming the capture candidate.',
            child: Column(
              children: [
                TextField(
                  controller: _amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _merchantController,
                  decoration: const InputDecoration(
                    labelText: 'Merchant / notes',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                PremiumRow(
                  icon: _type == 'income'
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  title: 'Type',
                  subtitle: transactionTypeLabel(_type),
                  onTap: _showTypePicker,
                ),
                const SizedBox(height: AppSpacing.sm),
                PremiumRow(
                  icon: selectedAccount == null
                      ? Icons.wallet_outlined
                      : accountIcon(selectedAccount),
                  title: 'Account',
                  subtitle: selectedAccount?.name ?? 'Choose account',
                  iconColor: selectedAccount?.color,
                  onTap: () => _showAccountPicker(state),
                ),
                const SizedBox(height: AppSpacing.sm),
                PremiumRow(
                  icon: categoryIcon(selectedCategory),
                  title: 'Category',
                  subtitle: selectedCategory == null
                      ? 'Choose category'
                      : categoryPath(state, selectedCategory),
                  iconColor: categoryColor(selectedCategory, context),
                  onTap: () => _showCategoryPicker(state),
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Raw message',
            child: Text(candidate.rawText ?? 'No raw payload stored.'),
          ),
          const Gap(AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                onPressed: candidate.status == 'pending'
                    ? () => _confirmCandidate(candidate, state)
                    : null,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Confirm'),
              ),
              OutlinedButton.icon(
                onPressed: candidate.status == 'pending'
                    ? () => _dismissCandidate()
                    : null,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _syncDraft(CaptureCandidate candidate, LedgerState state) {
    if (_loadedCandidateId == candidate.id) return;
    _loadedCandidateId = candidate.id;
    _amountController.text = candidate.parsedAmount == null
        ? ''
        : _formatAmountInput(candidate.parsedAmount!.amountMinor);
    _merchantController.text = candidate.merchant ?? '';
    _type = candidate.transactionType == 'income' ? 'income' : 'expense';
    _accountId =
        candidate.suggestedAccountId ??
        state.accounts.firstWhereOrNull((account) => !account.isArchived)?.id ??
        state.accounts.firstOrNull?.id;
    _categoryId =
        candidate.suggestedCategoryId ?? firstActiveCategory(state)?.id;
  }

  Future<void> _showTypePicker() async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Capture type',
      searchable: false,
      selectedValue: _type,
      options: const [
        PickerOption(
          value: 'expense',
          title: 'Expense',
          icon: Icons.trending_down_rounded,
        ),
        PickerOption(
          value: 'income',
          title: 'Income',
          icon: Icons.trending_up_rounded,
        ),
      ],
    );
    if (next == null) return;
    setState(() => _type = next);
  }

  Future<void> _showAccountPicker(LedgerState state) async {
    final next = await showFullScreenPicker<String>(
      context: context,
      title: 'Choose account',
      searchHint: 'Search accounts',
      selectedValue: _accountId,
      options: [
        for (final account in state.accounts.where(
          (account) => !account.isArchived,
        ))
          PickerOption(
            value: account.id,
            title: account.name,
            subtitle:
                '${accountTypeLabel(account.type)} · ${formatMoney(accountBalance(state, account), state.preferences.locale)}',
            icon: accountIcon(account),
            iconColor: account.color,
          ),
      ],
    );
    if (next == null) return;
    setState(() => _accountId = next);
  }

  Future<void> _showCategoryPicker(LedgerState state) async {
    final next = await showCategoryHierarchyPicker(
      context: context,
      state: state,
      selectedCategoryId: _categoryId,
    );
    if (next == null) return;
    setState(() => _categoryId = next);
  }

  Future<bool> _saveDraft(CaptureCandidate candidate, LedgerState state) async {
    final amountMinor = _amountMinorFromInput(_amountController.text);
    if (amountMinor <= 0) {
      _showCaptureMessage('Enter an amount before saving.');
      return false;
    }
    final account = accountById(state, _accountId);
    if (account == null) {
      _showCaptureMessage('Choose an account before saving.');
      return false;
    }
    await ref
        .read(ledgerProvider.notifier)
        .updateCaptureCandidateDetails(
          id: candidate.id,
          parsedAmount: Money(
            amountMinor: amountMinor,
            currency: account.currency,
          ),
          merchant: _merchantController.text,
          transactionType: _type,
          suggestedAccountId: account.id,
          suggestedCategoryId: _categoryId,
        );
    if (!mounted) return false;
    _showCaptureMessage('Capture draft saved.');
    return true;
  }

  Future<void> _confirmCandidate(
    CaptureCandidate candidate,
    LedgerState state,
  ) async {
    final saved = await _saveDraft(candidate, state);
    if (!saved) return;
    final router = GoRouter.of(context);
    try {
      router.push('/add?captureCandidateId=${candidate.id}');
    } catch (e) {
      if (!mounted) return;
      _showCaptureMessage(e.toString());
    }
  }

  Future<void> _dismissCandidate() async {
    await ref
        .read(ledgerProvider.notifier)
        .updateCaptureCandidateStatus(widget.candidateId, 'rejected');
    if (!mounted) return;
    _showCaptureMessage('Capture candidate marked rejected.');
  }

  void _showCaptureMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

String _formatAmountInput(int amountMinor) {
  if (amountMinor == 0) return '';
  final integer = amountMinor ~/ 100;
  final fraction = amountMinor % 100;
  if (fraction == 0) return '$integer';
  return '$integer.${fraction.toString().padLeft(2, '0')}';
}

int _amountMinorFromInput(String value) {
  final clean = value.replaceAll(RegExp(r'[^0-9.]'), '');
  if (clean.isEmpty) return 0;
  final parts = clean.split('.');
  final integer = int.tryParse(parts[0]) ?? 0;
  final fraction = parts.length > 1
      ? (int.tryParse(parts[1].padRight(2, '0').substring(0, 2)) ?? 0)
      : 0;
  return integer * 100 + fraction;
}
