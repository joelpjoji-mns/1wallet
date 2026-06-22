import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../capture/receipt_ocr.dart';
import 'add_record_widgets.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../utils/recurrence_utils.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../../widgets/currency_picker.dart';
import '../../utils/number_formatter.dart';
import '../common/category_hierarchy_picker.dart';
import '../common/full_screen_picker.dart';

class AddRecordScreen extends ConsumerStatefulWidget {
  const AddRecordScreen({
    super.key,
    this.transactionId,
    this.initialAccountId,
    this.plannedId,
    this.captureCandidateId,
    this.initialTab = 0,
  });

  final String? transactionId;
  final String? initialAccountId;
  final String? plannedId;
  final String? captureCandidateId;
  final int initialTab;

  @override
  ConsumerState<AddRecordScreen> createState() => _AddRecordScreenState();
}

class _AddRecordScreenState extends ConsumerState<AddRecordScreen> {
  var _type = 'expense';
  var _amount = '0';
  var _expression = '';
  int _activeField = 0; // 0 = main, 1 = local, 2 = counter
  String _localAmount = '';
  String _localExpression = '';
  String _counterAmount = '';
  String _counterExpression = '';
  String? _transactionCurrency;
  String? _accountId;
  String? _counterAccountId;
  String? _categoryId;
  String? _loadedTransactionId;
  final _notesController = TextEditingController();
  final _locationController = TextEditingController();
  final _paymentMethodController = TextEditingController();
  final _localAmountController = TextEditingController();
  final _counterAmountController = TextEditingController();
  final _charges = <_ChargeDraft>[];
  DateTime _occurredAt = DateTime.now();
  bool _isScanning = false;
  bool _localAmountEdited = false;
  bool _counterAmountEdited = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _accountId = widget.initialAccountId;
  }

  @override
  void dispose() {
    _notesController.dispose();
    _locationController.dispose();
    _paymentMethodController.dispose();
    _localAmountController.dispose();
    _counterAmountController.dispose();
    for (final charge in _charges) {
      charge.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final editingTransaction = widget.transactionId == null
        ? null
        : state.transactions.firstWhereOrNull(
            (transaction) => transaction.id == widget.transactionId,
          );
    final plannedTransaction = widget.plannedId == null
        ? null
        : state.transactions.firstWhereOrNull(
            (transaction) => transaction.id == widget.plannedId,
          );
    final captureCandidate = widget.captureCandidateId == null
        ? null
        : state.captureCandidates.firstWhereOrNull(
            (c) => c.id == widget.captureCandidateId,
          );
    _syncDrafts(editingTransaction, plannedTransaction, captureCandidate, state);
    _syncCreateDraftAccount(state, editingTransaction ?? plannedTransaction);
    _clearInvalidCategory(state, editingTransaction ?? plannedTransaction);
    final sourceAccount = accountById(state, _accountId);
    final counterAccount = accountById(state, _counterAccountId);
    final category = categoryById(state, _categoryId);
    final tone = _toneColor(context, _type);

    final txCurrency =
        _transactionCurrency ??
        sourceAccount?.currency ??
        state.preferences.baseCurrency;
    final isForeign =
        txCurrency.toUpperCase() !=
        (sourceAccount?.currency.toUpperCase() ??
            state.preferences.baseCurrency.toUpperCase());
    final isCrossTransfer =
        _type == 'transfer' &&
        counterAccount != null &&
        counterAccount.currency.toUpperCase() !=
            (sourceAccount?.currency.toUpperCase() ??
                state.preferences.baseCurrency.toUpperCase());
    _syncConvertedAmountDraft(
      state: state,
      sourceAccount: sourceAccount,
      counterAccount: counterAccount,
      txCurrency: txCurrency,
      isForeign: isForeign,
      isCrossTransfer: isCrossTransfer,
    );

    return DefaultTabController(
      length: 2,
      initialIndex: widget.initialTab,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.surface,
          elevation: 0,
          leading: IconButton(
            icon: Icon(
              Icons.arrow_back_rounded,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            },
          ),
          title: Text(
            editingTransaction == null ? 'Add record' : 'Edit record',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          actions: [
            IconButton(
              icon: _isScanning
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    )
                  : Icon(
                      Icons.camera_alt_outlined,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
              onPressed: _isScanning
                  ? null
                  : () => _scanReceipt(ImageSource.camera),
            ),
            IconButton(
              icon: Icon(
                Icons.check_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              onPressed: _saveRecord,
            ),
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: AddRecordTypeTabs(
                  value: _type,
                  onChanged: (value) => setState(() {
                    _type = value;
                    if (value == 'transfer') {
                      _categoryId = null;
                    }
                    if (value != 'transfer') _counterAccountId = null;
                  }),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: TabBar(
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    borderRadius: const BorderRadius.all(
                      Radius.circular(AppRadii.pill),
                    ),
                  ),
                  labelColor: Theme.of(context).colorScheme.onSecondaryContainer,
                  unselectedLabelColor: Theme.of(context).colorScheme.onSurfaceVariant,
                  tabs: const [
                    Tab(
                      height: 36,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.dialpad_rounded, size: 16),
                          SizedBox(width: 6),
                          Text('Keypad'),
                        ],
                      ),
                    ),
                    Tab(
                      height: 36,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notes_rounded, size: 16),
                          SizedBox(width: 6),
                          Text('Details'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(AppRadii.lg),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (_activeField == 1)
                        Text(
                          'Amount charged in ${sourceAccount?.currency ?? ""}',
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tone, fontWeight: FontWeight.w700),
                        )
                      else if (_activeField == 2)
                        Text(
                          'Amount received in ${counterAccount?.currency ?? ""}',
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tone, fontWeight: FontWeight.w700),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Builder(builder: (context) {
                                  final displayAmount = _activeField == 0
                                      ? _amount
                                      : _activeField == 1
                                          ? _localAmount
                                          : _activeField == 2
                                              ? _counterAmount
                                              : '0';
                                  final displayExpression = _activeField == 0
                                      ? _expression
                                      : _activeField == 1
                                          ? _localExpression
                                          : _activeField == 2
                                              ? _counterExpression
                                              : '';
                                  final fullText = displayExpression + (displayAmount.isEmpty ? '0' : displayAmount);
                                  return FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerRight,
                                    child: Text(
                                      (_type == 'income' || fullText == '0' ? '' : '-') +
                                          _formatExpression(fullText, state.preferences.locale),
                                      maxLines: 1,
                                      textAlign: TextAlign.right,
                                      style: Theme.of(context).textTheme.displayLarge?.copyWith(
                                            color: tone,
                                            fontWeight: FontWeight.w400,
                                            letterSpacing: -1.4,
                                          ),
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          PopupMenuButton<String>(
                            initialValue: txCurrency,
                            onSelected: (val) => setState(() {
                              _transactionCurrency = val;
                              _localAmountEdited = false;
                              _localAmount = '';
                              _localExpression = '';
                              _localAmountController.clear();
                            }),
                            itemBuilder: (context) => availableCurrencies(state)
                                .map((c) => PopupMenuItem(value: c, child: Text(c)))
                                .toList(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 7),
                              decoration: BoxDecoration(
                                color: tone.withAlpha(180),
                                borderRadius: BorderRadius.circular(AppRadii.pill),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    txCurrency,
                                    style: TextStyle(
                                      color: tone.computeLuminance() > 0.5
                                          ? Theme.of(context).colorScheme.onSurface
                                          : Theme.of(context).colorScheme.surface,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Icon(
                                    Icons.expand_more_rounded,
                                    size: 15,
                                    color: tone.computeLuminance() > 0.5
                                        ? Theme.of(context).colorScheme.onSurface
                                        : Theme.of(context).colorScheme.surface,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (isForeign || isCrossTransfer) ...[
                const SizedBox(height: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: _FxAmountPanel(
                    state: state,
                    sourceAccount: sourceAccount,
                    counterAccount: counterAccount,
                    txCurrency: txCurrency,
                    isForeign: isForeign,
                    isCrossTransfer: isCrossTransfer,
                    sentAmount: _resolvedMainAmountInput(),
                    localAmount: _localAmountController.text,
                    counterAmount: _counterAmountController.text,
                    activeField: _activeField,
                    onEditMain: () => setState(() => _activeField = 0),
                    onEditLocal: () => setState(() => _activeField = 1),
                    onEditCounter: () => setState(() => _activeField = 2),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                child: AddRecordSelectorGrid(
                  state: state,
                  sourceAccount: sourceAccount,
                  counterAccount: counterAccount,
                  category: category,
                  type: _type,
                  onSelectAccount: () => _showAccountPicker(false),
                  onSelectCounter: () => _showAccountPicker(true),
                  onSelectCategory: _showCategoryPicker,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: TabBarView(
                  children: [
                    AddRecordCalculatorPad(
                      type: _type,
                      onKey: (key) => setState(() {
                        if (_activeField == 0) {
                          final next = _applyKey(_amount, _expression, key);
                          _amount = next.amount;
                          _expression = next.expression;
                        } else if (_activeField == 1) {
                          _localAmountEdited = true;
                          final next = _applyKey(_localAmount, _localExpression, key);
                          _localAmount = next.amount;
                          _localExpression = next.expression;
                          _localAmountController.text = next.amount;
                        } else if (_activeField == 2) {
                          _counterAmountEdited = true;
                          final next = _applyKey(_counterAmount, _counterExpression, key);
                          _counterAmount = next.amount;
                          _counterExpression = next.expression;
                          _counterAmountController.text = next.amount;
                        }
                      }),
                    ),
                    ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        TextFormField(
                          controller: _notesController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Notes',
                            prefixIcon: const Icon(Icons.notes_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Expanded(
                              child: AddRecordTappableDetailField(
                                icon: Icons.today_outlined,
                                label: formatLedgerDate(_occurredAt, state.preferences.locale),
                                onTap: _selectDate,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: AddRecordTappableDetailField(
                                icon: Icons.schedule_outlined,
                                label: DateFormat.Hm().format(_occurredAt),
                                onTap: _selectTime,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        TextFormField(
                          controller: _locationController,
                          decoration: InputDecoration(
                            labelText: 'Place',
                            prefixIcon: const Icon(Icons.place_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        TextFormField(
                          controller: _paymentMethodController,
                          decoration: InputDecoration(
                            labelText: 'Payment method',
                            prefixIcon: const Icon(Icons.payment_outlined),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        DropdownButtonFormField<String>(
                          value: _status ?? 'cleared',
                          decoration: InputDecoration(
                            labelText: 'Status',
                            prefixIcon: const Icon(Icons.info_outline),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadii.md)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'cleared', child: Text('Cleared')),
                            DropdownMenuItem(value: 'pending', child: Text('Pending')),
                            DropdownMenuItem(value: 'void', child: Text('Skipped / Void')),
                          ],
                          onChanged: (val) => setState(() => _status = val),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.icon(
                          onPressed: _saveRecord,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save record'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _CalcState _applyKey(String amount, String expression, String key) {
    if (key == 'AC') return const _CalcState(amount: '0', expression: '');
    if (key == '⌫') {
      final next = amount.length <= 1 ? '0' : amount.substring(0, amount.length - 1);
      return _CalcState(amount: next, expression: expression);
    }
    if (key == '.') {
      if (amount.contains('.')) return _CalcState(amount: amount, expression: expression);
      return _CalcState(amount: amount.isEmpty ? '0.' : '$amount.', expression: expression);
    }
    if (RegExp(r'^\d$').hasMatch(key)) {
      return _CalcState(amount: amount == '0' ? key : '$amount$key', expression: expression);
    }
    if (key == '=') {
      if (expression.isNotEmpty) {
        final cur = amount.trim().isEmpty ? '0' : amount;
        return _CalcState(amount: _evaluate('$expression $cur'), expression: '');
      }
      return _CalcState(amount: amount, expression: '');
    }
    if (['+', '-', 'x', '/'].contains(key)) {
      final op = key == 'x' ? '*' : key;
      final cur = amount.isEmpty ? '0' : amount;
      if (expression.isNotEmpty && amount.isNotEmpty) {
        return _CalcState(amount: '', expression: '${_evaluate("$expression $cur")} $op');
      }
      return _CalcState(amount: '', expression: '$cur $op');
    }
    return _CalcState(amount: amount, expression: expression);
  }

  String _evaluate(String expr) {
    try {
      final tokens = expr.trim().split(RegExp(r'\s+'));
      if (tokens.isEmpty) return '0';
      final values = <double>[];
      final ops = <String>[];
      for (final t in tokens) {
        final n = double.tryParse(t);
        if (n != null) values.add(n);
        else ops.add(t);
      }
      var result = values.isNotEmpty ? values[0] : 0.0;
      for (var i = 0; i < ops.length; i++) {
        if (ops[i] == '+') result += values[i + 1];
        if (ops[i] == '-') result -= values[i + 1];
        if (ops[i] == '*') result *= values[i + 1];
        if (ops[i] == '/') result /= values[i + 1] != 0 ? values[i + 1] : 1;
      }
      return _trimNumber(result);
    } catch (_) { return '0'; }
  }

  Future<void> _scanReceipt(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source);
    if (file == null) return;
    setState(() => _isScanning = true);
    try {
      final state = ref.read(ledgerProvider);
      final fields = await extractReceiptFieldsFromPhoto(file.path, ReceiptPhotoOptions(
          fallbackCurrency: state.preferences.baseCurrency,
          fallbackOccurredAt: DateTime.now().toIso8601String(),
          fileName: file.name,
      ));
      if (!mounted) return;
      setState(() {
        if (fields.amountMinor != null) _amount = _formatAmountInput(fields.amountMinor!, state.preferences.baseCurrency);
        if (fields.merchant != null) _notesController.text = fields.merchant!;
      });
    } catch (_) {}
    finally { if (mounted) setState(() => _isScanning = false); }
  }

  Future<void> _showAccountPicker(bool counter) async {
    final state = ref.read(ledgerProvider);
    final accounts = sortAccounts(
      state.accounts.where((a) => counter ? a.id != _accountId : !a.isArchived),
    );
    final nextId = await showFullScreenPicker<String>(
      context: context,
      title: counter ? 'Destination' : 'Account',
      selectedValue: counter ? _counterAccountId : _accountId,
      options: [
        for (final a in accounts)
          PickerOption(
            value: a.id,
            title: a.name,
            subtitle: '${a.currency} · ${formatMoney(accountBalance(state, a), state.preferences.locale)}',
            icon: accountIcon(a),
            iconColor: accountDisplayColor(a),
          ),
      ],
    );
    if (nextId != null) setState(() { if (counter) _counterAccountId = nextId; else _accountId = nextId; });
  }

  Future<void> _showCategoryPicker() async {
    final state = ref.read(ledgerProvider);
    final nextId = await showCategoryHierarchyPicker(context: context, state: state, selectedCategoryId: _categoryId);
    if (nextId != null) setState(() => _categoryId = nextId);
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(context: context, initialDate: _occurredAt, firstDate: DateTime(2000), lastDate: DateTime(2100));
    if (picked != null) setState(() => _occurredAt = DateTime(picked.year, picked.month, picked.day, _occurredAt.hour, _occurredAt.minute));
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_occurredAt));
    if (picked != null) setState(() => _occurredAt = DateTime(_occurredAt.year, _occurredAt.month, _occurredAt.day, picked.hour, picked.minute));
  }

  String _resolvedMainAmountInput() => _expression.isNotEmpty ? _evaluate('$_expression ${_amount.isEmpty ? "0" : _amount}') : _amount;

  void _syncConvertedAmountDraft({required LedgerState state, required Account? sourceAccount, required Account? counterAccount, required String txCurrency, required bool isForeign, required bool isCrossTransfer}) {
    final parsedMinor = _amountMinorFromInput(_resolvedMainAmountInput(), txCurrency);
    if (parsedMinor <= 0) return;
    if (isForeign && sourceAccount != null && !_localAmountEdited) {
      _localAmountController.text = _convertedAmountInput(state: state, amountMinor: parsedMinor, fromCurrency: txCurrency, toCurrency: sourceAccount.currency);
      _localAmount = _localAmountController.text;
    }
    if (isCrossTransfer && counterAccount != null && !_counterAmountEdited) {
      _counterAmountController.text = _convertedAmountInput(state: state, amountMinor: parsedMinor, fromCurrency: txCurrency, toCurrency: counterAccount.currency);
      _counterAmount = _counterAmountController.text;
    }
  }

  String _convertedAmountInput({required LedgerState state, required int amountMinor, required String fromCurrency, required String toCurrency}) {
    final converted = convertMoneyForDisplay(state, Money(amountMinor: amountMinor, currency: fromCurrency), toCurrency);
    return _formatAmountInput(converted.amountMinor, toCurrency);
  }

  Future<void> _saveRecord() async {
    final state = ref.read(ledgerProvider);
    final account = accountById(state, _accountId);
    if (account == null) { _showMessage('Choose an account.'); return; }
    
    final txCurrency = _transactionCurrency ?? account.currency;
    final parsedMinor = _amountMinorFromInput(_resolvedMainAmountInput(), txCurrency);
    if (parsedMinor <= 0) { _showMessage('Enter an amount.'); return; }

    int finalAmountMinor = 0;
    int? finalOriginalAmountMinor;
    String? finalOriginalCurrency;
    int? finalCounterAmountMinor;

    if (txCurrency.toUpperCase() == account.currency.toUpperCase()) {
      finalAmountMinor = parsedMinor;
    } else {
      finalOriginalAmountMinor = parsedMinor;
      finalOriginalCurrency = txCurrency;
      finalAmountMinor = _amountMinorFromInput(_localAmountController.text, account.currency);
    }

    final counterAcc = accountById(state, _counterAccountId);
    if (_type == 'transfer' && counterAcc != null) {
      finalCounterAmountMinor = _amountMinorFromInput(_counterAmountController.text, counterAcc.currency);
    }

    final selectedCategory = categoryById(state, _categoryId);
    if (_type != 'transfer' && selectedCategory == null) { _showMessage('Choose a category.'); return; }

    try {
      final editingTransaction = widget.transactionId == null ? null : state.transactions.firstWhereOrNull((t) => t.id == widget.transactionId);
      final plannedTransaction = widget.plannedId == null ? null : state.transactions.firstWhereOrNull((t) => t.id == widget.plannedId);
      final savedTx = await ref.read(ledgerProvider.notifier).upsertTransaction(
        id: widget.transactionId,
        type: _type,
        accountId: account.id,
        counterAccountId: _counterAccountId,
        amountMinor: finalAmountMinor,
        originalAmountMinor: finalOriginalAmountMinor,
        originalCurrency: finalOriginalCurrency,
        counterAmountMinor: finalCounterAmountMinor,
        categoryId: _type == 'transfer' ? null : selectedCategory!.id,
        status: _status ?? editingTransaction?.status ?? 'cleared',
        source: editingTransaction?.source ?? plannedTransaction?.source ?? 'manual',
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        occurredAt: _occurredAt,
        originalTransactionId: widget.plannedId ?? editingTransaction?.originalTransactionId,
      );

      if (plannedTransaction != null &&
          plannedTransaction.recurrenceFrequency != null &&
          plannedTransaction.recurrenceFrequency != 'manual') {
        final nextDate = advanceTransactionRecurrence(plannedTransaction.occurredAt, plannedTransaction);
        await ref.read(ledgerProvider.notifier).updateTransactionStatus(widget.plannedId!, 'scheduled', occurredAt: nextDate);
      }

      if (widget.captureCandidateId != null) {
        await ref.read(ledgerProvider.notifier).updateCaptureCandidateStatus(widget.captureCandidateId!, 'approved');
      }

      if (!mounted) return;
      if (context.canPop()) context.pop(); else context.go('/');
    } catch (e) { _showMessage(e.toString()); }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  void _syncDrafts(TransactionRecord? tx, TransactionRecord? planned, CaptureCandidate? candidate, LedgerState state) {
    final hasCapture = widget.captureCandidateId != null;
    final key = tx?.id ?? planned?.id ?? (hasCapture ? 'cap_${widget.captureCandidateId}' : '__new__');
    if (_loadedTransactionId == key) return;
    _loadedTransactionId = key;

    if (hasCapture && candidate != null) {
      _type = candidate.transactionType == 'income' ? 'income' : 'expense';
      _accountId = candidate.suggestedAccountId ?? accountById(state, _accountId)?.id ?? state.accounts.firstWhereOrNull((a) => !a.isArchived)?.id;
      _categoryId = candidate.suggestedCategoryId;
      _notesController.text = candidate.merchant ?? candidate.rawText ?? '';
      if (candidate.parsedAmount != null) {
        _transactionCurrency = candidate.parsedAmount!.currency;
        _amount = _formatAmountInput(candidate.parsedAmount!.amountMinor, _transactionCurrency!);
      }
      _occurredAt = candidate.createdAt;
    } else {
      final source = tx ?? planned;
      if (source == null) return;
      _type = source.type;
      _accountId = source.accountId;
      _counterAccountId = source.counterAccountId;
      _categoryId = source.categoryId;
      _notesController.text = source.notes ?? '';
      _transactionCurrency = source.originalAmount?.currency ?? source.amount.currency;
      _amount = _formatAmountInput((source.originalAmount ?? source.amount).amountMinor, _transactionCurrency!);
      _status = (tx == null && planned != null) ? 'cleared' : source.status;
    }
  }

  void _syncCreateDraftAccount(LedgerState state, TransactionRecord? source) {
    if (source != null || _accountId != null) return;
    _accountId = state.accounts.firstOrNull?.id;
  }

  void _clearInvalidCategory(LedgerState state, TransactionRecord? source) {
    if (source != null || _type == 'transfer') return;
    if (categoryById(state, _categoryId) == null) _categoryId = null;
  }
}

class _FxAmountPanel extends StatelessWidget {
  const _FxAmountPanel({required this.state, required this.sourceAccount, required this.counterAccount, required this.txCurrency, required this.isForeign, required this.isCrossTransfer, required this.sentAmount, required this.localAmount, required this.counterAmount, required this.activeField, required this.onEditMain, required this.onEditLocal, required this.onEditCounter});
  final LedgerState state; final Account? sourceAccount; final Account? counterAccount; final String txCurrency; final bool isForeign; final bool isCrossTransfer; final String sentAmount; final String localAmount; final String counterAmount; final int activeField; final VoidCallback onEditMain; final VoidCallback onEditLocal; final VoidCallback onEditCounter;
  @override
  Widget build(BuildContext context) {
    if (isCrossTransfer && counterAccount != null) {
      return Row(children: [
        Expanded(child: _FxAmountCard(title: 'Sent', subtitle: sourceAccount?.name ?? '', amount: sentAmount, currency: txCurrency, icon: Icons.upload_rounded, selected: activeField == 0, onTap: onEditMain)),
        const SizedBox(width: 8),
        Expanded(child: _FxAmountCard(title: 'Received', subtitle: counterAccount!.name, amount: counterAmount, currency: counterAccount!.currency, icon: Icons.download_rounded, selected: activeField == 2, onTap: onEditCounter)),
      ]);
    }
    if (isForeign && sourceAccount != null) {
      return Row(children: [
        Expanded(child: _FxAmountCard(title: 'Original', subtitle: 'Transaction', amount: sentAmount, currency: txCurrency, icon: Icons.receipt_long_outlined, selected: activeField == 0, onTap: onEditMain)),
        const SizedBox(width: 8),
        Expanded(child: _FxAmountCard(title: 'Charged', subtitle: sourceAccount!.name, amount: localAmount, currency: sourceAccount!.currency, icon: Icons.currency_exchange_rounded, selected: activeField == 1, onTap: onEditLocal)),
      ]);
    }
    return const SizedBox.shrink();
  }
}

class _FxAmountCard extends StatelessWidget {
  const _FxAmountCard({required this.title, required this.subtitle, required this.amount, required this.currency, required this.icon, required this.selected, required this.onTap});
  final String title; final String subtitle; final String amount; final String currency; final IconData icon; final bool selected; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Material(
      color: selected ? scheme.primaryContainer.withAlpha(110) : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(AppRadii.md), child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadii.md), border: Border.all(color: selected ? scheme.primary : scheme.outlineVariant)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 14, color: color), const SizedBox(width: 4), Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800))]),
          const SizedBox(height: 4),
          Text('$amount $currency', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
          Text(subtitle, style: const TextStyle(fontSize: 10)),
        ]),
      )),
    );
  }
}

class _CalcState { const _CalcState({required this.amount, required this.expression}); final String amount; final String expression; }
class _ChargeDraft { _ChargeDraft({required this.id, required this.labelController, required this.amountController}); final String id; final TextEditingController labelController; final TextEditingController amountController; void dispose() { labelController.dispose(); amountController.dispose(); } }

Color _toneColor(BuildContext context, String type) {
  final scheme = Theme.of(context).colorScheme;
  if (type == 'income') return Theme.of(context).brightness == Brightness.dark ? AppColors.positiveDark : AppColors.positiveLight;
  return type == 'transfer' ? scheme.primary : scheme.error;
}

int _amountMinorFromInput(String value, [String? currency]) {
  final clean = value.replaceAll(RegExp(r'[^0-9.]'), '');
  if (clean.isEmpty) return 0;
  final parts = clean.split('.');
  final integer = int.tryParse(parts[0]) ?? 0;
  final minors = currency != null ? minorUnits(currency) : 2;
  final fraction = parts.length > 1 ? (int.tryParse(parts[1].padRight(minors, '0').substring(0, minors)) ?? 0) : 0;
  return (integer * math.pow(10, minors).toInt()) + fraction;
}

String _formatAmountInput(int amountMinor, [String? currency]) {
  final minors = currency != null ? minorUnits(currency) : 2;
  final amount = amountMinor / math.pow(10, minors);
  if (amount == amount.roundToDouble()) return amount.round().toString();
  return amount.toStringAsFixed(minors).replaceFirst(RegExp(r'0$'), '');
}

String _trimNumber(double value) => value.isFinite ? value.toString().replaceAll(RegExp(r'\.0$'), '') : '0';

String _formatExpression(String expr, String locale) => formatNumberExpression(expr, locale);

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final v in this) if (test(v)) return v;
    return null;
  }
}
