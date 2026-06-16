import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';

import '../capture/receipt_ocr.dart';
import 'add_record_widgets.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../common/category_hierarchy_picker.dart';
import '../common/full_screen_picker.dart';
String _formatExpression(String expression, String locale) {
  if (expression.isEmpty) return expression;
  final buffer = StringBuffer();
  final numberBuffer = StringBuffer();
  
  final formatter = NumberFormat.decimalPattern(locale);
  
  void flushNumber() {
    if (numberBuffer.isEmpty) return;
    final numStr = numberBuffer.toString();
    numberBuffer.clear();
    
    if (numStr == '.') {
      buffer.write('.');
      return;
    }
    
    final parts = numStr.split('.');
    final whole = parts[0];
    if (whole.isNotEmpty && whole != '-') {
      final parsed = int.tryParse(whole);
      if (parsed != null) {
        buffer.write(formatter.format(parsed));
      } else {
        buffer.write(whole);
      }
    } else if (whole == '-') {
      buffer.write('-');
    }
    
    if (parts.length > 1) {
      buffer.write('.');
      buffer.write(parts[1]); 
    } else if (numStr.endsWith('.')) {
      buffer.write('.');
    }
  }

  for (int i = 0; i < expression.length; i++) {
    final char = expression[i];
    if (char == '+' || char == '-' || char == '*' || char == '/' || char == ' ' || char == '=') {
      flushNumber();
      buffer.write(char);
    } else {
      numberBuffer.write(char);
    }
  }
  flushNumber();
  return buffer.toString();
}

class AddRecordScreen extends ConsumerStatefulWidget {
  const AddRecordScreen({
    super.key,
    this.transactionId,
    this.initialAccountId,
    this.initialTab = 0,
  });

  final String? transactionId;
  final String? initialAccountId;
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
    _syncEditDraft(editingTransaction, state);
    _syncCreateDraftAccount(state, editingTransaction);
    _clearInvalidCategory(state, editingTransaction);
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
              // Type tabs
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
              const Gap(AppSpacing.sm),

              // Panel tabs (Keypad / Details)
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
                  labelColor: Theme.of(
                    context,
                  ).colorScheme.onSecondaryContainer,
                  unselectedLabelColor: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant,
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
              const Gap(AppSpacing.sm),

              // Amount display
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
                      // Expression line or active label
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
                        )
                      else if (_activeField >= 3 && _activeField - 3 < _charges.length)
                        Text(
                          'Charge: ${_charges[_activeField - 3].labelController.text.isEmpty ? "Split fee" : _charges[_activeField - 3].labelController.text}',
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
                                              : (_activeField >= 3 && _activeField - 3 < _charges.length)
                                                  ? _charges[_activeField - 3].amountController.text.replaceAll(',', '').trim()
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
                                      (_type == 'income' || fullText == '0'
                                              ? ''
                                              : '-') +
                                          _formatExpression(fullText, state.preferences.locale),
                                      maxLines: 1,
                                      textAlign: TextAlign.right,
                                      style: Theme.of(context)
                                          .textTheme
                                          .displayLarge
                                          ?.copyWith(
                                            color: tone,
                                            fontWeight: FontWeight.w400,
                                            letterSpacing: -1.4,
                                          ),
                                    ),
                                  );
                                }),
                                Builder(builder: (context) {
                                  final displayAmount = _activeField == 0
                                      ? _amount
                                      : _activeField == 1
                                          ? _localAmount
                                          : _activeField == 2
                                              ? _counterAmount
                                              : (_activeField >= 3 && _activeField - 3 < _charges.length)
                                                  ? _charges[_activeField - 3].amountController.text.replaceAll(',', '').trim()
                                                  : '0';

                                  final displayExpression = _activeField == 0
                                      ? _expression
                                      : _activeField == 1
                                          ? _localExpression
                                          : _activeField == 2
                                              ? _counterExpression
                                              : '';
                                              
                                  final fullText = displayExpression + (displayAmount.isEmpty ? '0' : displayAmount);
                                  final evaluated = displayExpression.isNotEmpty ? _evaluate(fullText) : displayAmount;

                                  return Text(
                                    (displayExpression.isNotEmpty ? '= ' : '') + _amountWords(evaluated),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: tone.withAlphaFactor(0.75),
                                          fontStyle: FontStyle.italic,
                                        ),
                                  );
                                }),
                              ],
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          // Currency chip
                          PopupMenuButton<String>(
                            initialValue: txCurrency,
                            onSelected: (val) => setState(() {
                              _transactionCurrency = val;
                              _localAmountEdited = false;
                              _localAmount = '';
                              _localExpression = '';
                              _localAmountController.clear();
                              if (!_counterAmountEdited) {
                                _counterAmount = '';
                                _counterExpression = '';
                                _counterAmountController.clear();
                              }
                            }),
                            itemBuilder: (context) => availableCurrencies(state)
                                .map((c) => PopupMenuItem(value: c, child: Text(c)))
                                .toList(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.sm,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: tone.withAlphaFactor(0.72),
                                borderRadius: BorderRadius.circular(AppRadii.pill),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    txCurrency,
                                    style: TextStyle(
                                      color: tone.computeLuminance() > 0.5
                                          ? Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                          : Theme.of(context)
                                                .colorScheme
                                                .surface,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Icon(
                                    Icons.expand_more_rounded,
                                    size: 15,
                                    color: tone.computeLuminance() > 0.5
                                        ? Theme.of(context)
                                              .colorScheme
                                              .onSurface
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
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
                    onEditMain: () {
                      setState(() => _activeField = 0);
                      DefaultTabController.of(context).animateTo(0);
                    },
                    onEditLocal: () {
                      setState(() {
                        _activeField = 1;
                        _localAmountEdited = true;
                        _localAmount = _localAmountController.text
                            .replaceAll(',', '')
                            .trim();
                      });
                      DefaultTabController.of(context).animateTo(0);
                    },
                    onEditCounter: () {
                      setState(() {
                        _activeField = 2;
                        _counterAmountEdited = true;
                        _counterAmount = _counterAmountController.text
                            .replaceAll(',', '')
                            .trim();
                      });
                      DefaultTabController.of(context).animateTo(0);
                    },
                  ),
                ),
              ],
              const Gap(AppSpacing.sm),

              // Account/Category selector
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
              const Gap(AppSpacing.sm),

              // Tab views: keypad / details
              Expanded(
                child: TabBarView(
                  children: [
                    // ── Keypad tab ──────────────────────────────────────────
                    AddRecordCalculatorPad(
                      type: _type,
                      onKey: (key) => setState(() {
                        if (_activeField == 0) {
                          final next = _applyKey(_amount, _expression, key);
                          _amount = next.amount;
                          _expression = next.expression;
                        } else if (_activeField == 1) {
                          _localAmountEdited = true;
                          final next = _applyKey(
                            _localAmount,
                            _localExpression,
                            key,
                          );
                          _localAmount = next.amount;
                          _localExpression = next.expression;
                          _localAmountController.text = next.amount;
                        } else if (_activeField == 2) {
                          _counterAmountEdited = true;
                          final next = _applyKey(
                            _counterAmount,
                            _counterExpression,
                            key,
                          );
                          _counterAmount = next.amount;
                          _counterExpression = next.expression;
                          _counterAmountController.text = next.amount;
                        } else if (_activeField >= 3 && _activeField - 3 < _charges.length) {
                          final chargeIdx = _activeField - 3;
                          final chargeAmount = _charges[chargeIdx].amountController.text.replaceAll(',', '').trim();
                          final next = _applyKey(chargeAmount.isEmpty ? '0' : chargeAmount, '', key);
                          _charges[chargeIdx].amountController.text = next.amount;
                        }
                      }),
                    ),
                    // ── Details tab ─────────────────────────────────────────
                    ListView(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      children: [
                        // Notes
                        TextFormField(
                          controller: _notesController,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Notes',
                            prefixIcon: const Icon(Icons.notes_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadii.md),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),

                        // Date + Time
                        Row(
                          children: [
                            Expanded(
                              child: AddRecordTappableDetailField(
                                icon: Icons.today_outlined,
                                label: formatLedgerDate(
                                  _occurredAt,
                                  state.preferences.locale,
                                ),
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

                        // Place / location
                        TextFormField(
                          controller: _locationController,
                          decoration: InputDecoration(
                            labelText: 'Place',
                            hintText: 'e.g. Supermarket, Restaurant…',
                            prefixIcon: const Icon(Icons.place_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadii.md),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Payment Method
                        TextFormField(
                          controller: _paymentMethodController,
                          decoration: InputDecoration(
                            labelText: 'Payment method',
                            hintText: 'e.g. Auto debit, Check, Cash...',
                            prefixIcon: const Icon(Icons.payment_outlined),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadii.md),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Split Charges
                        if (_charges.isNotEmpty) ...[
                          Text(
                            'Split charges & fees',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          for (int i = 0; i < _charges.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(
                                bottom: AppSpacing.sm,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 2,
                                    child: TextFormField(
                                      controller: _charges[i].labelController,
                                      decoration: InputDecoration(
                                        hintText: 'Charge name (e.g. Bank fee)',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            AppRadii.md,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _charges[i].amountController,
                                      readOnly: true,
                                      onTap: () {
                                        setState(() => _activeField = 3 + i);
                                        DefaultTabController.of(context).animateTo(0);
                                      },
                                      decoration: InputDecoration(
                                        hintText: 'Amount',
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            AppRadii.md,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      Icons.remove_circle_outline,
                                      color: Theme.of(context).colorScheme.error,
                                    ),
                                    onPressed: () {
                                      setState(() {
                                        _charges[i].dispose();
                                        _charges.removeAt(i);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                        ],
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _charges.add(
                                _ChargeDraft(
                                  id: DateTime.now().millisecondsSinceEpoch
                                      .toString(),
                                  labelController: TextEditingController(),
                                  amountController: TextEditingController(),
                                ),
                              );
                            });
                          },
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('Add split charge / fee'),
                          style: TextButton.styleFrom(
                            alignment: Alignment.centerLeft,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),

                        // Save button (details page)
                        FilledButton.icon(
                          onPressed: _saveRecord,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Save record'),
                        ),
                        const SizedBox(height: AppSpacing.sm),

                        // Receipt scan
                        OutlinedButton.icon(
                          onPressed: _isScanning
                              ? null
                              : () => _scanReceipt(ImageSource.camera),
                          icon: _isScanning
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.camera_alt_outlined),
                          label: Text(
                            _isScanning ? 'Scanning…' : 'Scan receipt',
                          ),
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

  // ── Calculator logic ──────────────────────────────────────────────────────

  _CalcState _applyKey(
    String currentAmount,
    String currentExpression,
    String key,
  ) {
    if (key == 'AC') {
      return const _CalcState(amount: '0', expression: '');
    }
    if (key == '⌫') {
      final next = currentAmount.length <= 1
          ? '0'
          : currentAmount.substring(0, currentAmount.length - 1);
      return _CalcState(amount: next, expression: currentExpression);
    }
    if (key == '.') {
      if (currentAmount.contains('.')) {
        return _CalcState(amount: currentAmount, expression: currentExpression);
      }
      final next = currentAmount.isEmpty ? '0.' : '$currentAmount.';
      return _CalcState(amount: next, expression: currentExpression);
    }
    if (RegExp(r'^\d$').hasMatch(key)) {
      final next = currentAmount == '0' ? key : '$currentAmount$key';
      return _CalcState(amount: next, expression: currentExpression);
    }
    if (key == '+/-') {
      if (currentAmount.isEmpty || currentAmount == '0') {
        return _CalcState(amount: currentAmount, expression: currentExpression);
      }
      final next = currentAmount.startsWith('-')
          ? currentAmount.substring(1)
          : '-$currentAmount';
      return _CalcState(amount: next, expression: currentExpression);
    }
    if (key == '%') {
      final parsed = double.tryParse(currentAmount) ?? 0;
      return _CalcState(
        amount: _trimNumber(parsed / 100),
        expression: currentExpression,
      );
    }
    // Operator keys (+, -, x, /)
    if (key == '+' || key == '-' || key == 'x' || key == '/') {
      final op = key == 'x' ? '*' : key;
      final cur = currentAmount.trim().isEmpty ? '0' : currentAmount;
      if (currentExpression.isNotEmpty && currentAmount.isNotEmpty) {
        final evaluated = _evaluate('$currentExpression $cur');
        return _CalcState(amount: '', expression: '$evaluated $op');
      } else if (currentExpression.isNotEmpty) {
        // replace trailing operator
        final expr = currentExpression.replaceAll(
          RegExp(r'[+\-*/]\s*$'),
          '$op ',
        );
        return _CalcState(amount: '', expression: expr);
      } else {
        return _CalcState(amount: '', expression: '$cur $op');
      }
    }
    if (key == '=') {
      if (currentExpression.isNotEmpty) {
        final cur = currentAmount.trim().isEmpty ? '0' : currentAmount;
        final result = _evaluate('$currentExpression $cur');
        return _CalcState(amount: result, expression: '');
      }
      return _CalcState(amount: currentAmount, expression: '');
    }
    return _CalcState(amount: currentAmount, expression: currentExpression);
  }

  /// Safely evaluates a simple arithmetic expression like "12 + 5 * 3"
  String _evaluate(String expr) {
    try {
      // Tokenise into numbers and operators
      final tokens = expr.trim().split(RegExp(r'\s+'));
      if (tokens.isEmpty) return '0';
      // Two passes: * and / first, then + and -
      final values = <double>[];
      final ops = <String>[];
      for (final token in tokens) {
        final n = double.tryParse(token);
        if (n != null) {
          values.add(n);
        } else if (token == '+' ||
            token == '-' ||
            token == '*' ||
            token == '/') {
          ops.add(token);
        }
      }
      // Process * and /
      var i = 0;
      while (i < ops.length) {
        if (ops[i] == '*' || ops[i] == '/') {
          final a = values[i];
          final b = values[i + 1];
          values[i] = (ops[i] == '*' ? a * b : (b != 0 ? a / b : 0)).toDouble();
          values.removeAt(i + 1);
          ops.removeAt(i);
        } else {
          i++;
        }
      }
      // Process + and -
      var result = values.isNotEmpty ? values[0] : 0.0;
      for (var j = 0; j < ops.length; j++) {
        if (ops[j] == '+') result += values[j + 1];
        if (ops[j] == '-') result -= values[j + 1];
      }
      return _trimNumber(result);
    } catch (_) {
      return '0';
    }
  }

  // ── Receipt scanning ──────────────────────────────────────────────────────

  Future<void> _scanReceipt(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source);
    if (file == null) return;

    setState(() => _isScanning = true);
    try {
      final state = ref.read(ledgerProvider);
      final fields = await extractReceiptFieldsFromPhoto(
        file.path,
        ReceiptPhotoOptions(
          fallbackCurrency: state.preferences.baseCurrency,
          fallbackOccurredAt: DateTime.now().toIso8601String(),
          fileName: file.name,
        ),
      );

      if (!mounted) return;
      if (fields.status == ReceiptOcrStatus.failed) {
        _showMessage(
          'Failed to scan receipt: ${fields.errorMessage ?? "Unknown error"}',
        );
        return;
      }

      setState(() {
        if (fields.amountMinor != null) {
          _amount = _formatAmountInput(fields.amountMinor!);
        }
        if (fields.merchant != null) {
          _notesController.text =
              fields.merchant! +
              (fields.notes != null ? ' - ${fields.notes}' : '');
        }
      });
      _showMessage('Receipt scanned successfully!');
    } catch (e) {
      if (mounted) _showMessage('Error scanning receipt: $e');
    } finally {
      if (mounted) setState(() => _isScanning = false);
    }
  }

  // ── Pickers ───────────────────────────────────────────────────────────────



  Future<void> _showAccountPicker(bool counter) async {
    final state = ref.read(ledgerProvider);
    final accounts = state.accounts
        .where(
          (account) => counter ? account.id != _accountId : !account.isArchived,
        )
        .toList()
      ..sort((a, b) {
        final homeA = a.showOnHome ? 0 : 1;
        final homeB = b.showOnHome ? 0 : 1;
        final homeCmp = homeA.compareTo(homeB);
        if (homeCmp != 0) return homeCmp;

        final sortCmp = a.sortOrder.compareTo(b.sortOrder);
        if (sortCmp != 0) return sortCmp;

        return a.name.compareTo(b.name);
      });
    final nextId = await showFullScreenPicker<String>(
      context: context,
      title: counter ? 'Choose destination' : 'Choose account',
      searchHint: 'Search accounts',
      selectedValue: counter ? _counterAccountId : _accountId,
      actionIcon: counter ? null : Icons.add_rounded,
      actionTooltip: counter ? null : 'Add account',
      onAction: counter
          ? null
          : () {
              Navigator.of(context).pop();
              context.push('/account/new');
            },
      options: [
        for (final account in accounts)
          PickerOption(
            value: account.id,
            title: account.name,
            subtitle:
                '${accountTypeLabel(account.type)} · ${account.currency} · ${formatMoney(accountBalance(state, account), state.preferences.locale)}',
            icon: accountIcon(account),
            iconColor: accountDisplayColor(account),
            searchText:
                '${account.institution ?? ''} ${account.groupName ?? ''} ${account.currency}',
          ),
      ],
    );
    if (nextId == null) return;
    setState(() {
      if (counter) {
        _counterAccountId = nextId;
        _counterAmountEdited = false;
        _counterAmount = '';
        _counterExpression = '';
        _counterAmountController.clear();
      } else {
        _accountId = nextId;
        _localAmountEdited = false;
        _localAmount = '';
        _localExpression = '';
        _localAmountController.clear();
        if (_counterAccountId == nextId) {
          _counterAccountId = null;
        }
        _counterAmountEdited = false;
        _counterAmount = '';
        _counterExpression = '';
        _counterAmountController.clear();
      }
    });
  }

  Future<void> _showCategoryPicker() async {
    final state = ref.read(ledgerProvider);
    final nextId = await showCategoryHierarchyPicker(
      context: context,
      state: state,
      selectedCategoryId: _categoryId,
    );
    if (nextId == null) return;
    setState(() => _categoryId = nextId);
  }



  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _occurredAt = DateTime(
          picked.year,
          picked.month,
          picked.day,
          _occurredAt.hour,
          _occurredAt.minute,
        );
      });
    }
  }

  Future<void> _selectTime() async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (picked != null) {
      setState(() {
        _occurredAt = DateTime(
          _occurredAt.year,
          _occurredAt.month,
          _occurredAt.day,
          picked.hour,
          picked.minute,
        );
      });
    }
  }

  String _resolvedMainAmountInput() {
    return _expression.isNotEmpty
        ? _evaluate('$_expression ${_amount.isEmpty ? "0" : _amount}')
        : _amount;
  }

  void _syncConvertedAmountDraft({
    required LedgerState state,
    required Account? sourceAccount,
    required Account? counterAccount,
    required String txCurrency,
    required bool isForeign,
    required bool isCrossTransfer,
  }) {
    final parsedAmountMinor = _amountMinorFromInput(_resolvedMainAmountInput());
    if (parsedAmountMinor <= 0) return;

    if (isForeign && sourceAccount != null && !_localAmountEdited) {
      final converted = _convertedAmountInput(
        state: state,
        amountMinor: parsedAmountMinor,
        fromCurrency: txCurrency,
        toCurrency: sourceAccount.currency,
      );
      _setConvertedDraft(
        controller: _localAmountController,
        value: converted,
        updateDraft: (value) => _localAmount = value,
        activeField: 1,
      );
    }

    if (isCrossTransfer && counterAccount != null && !_counterAmountEdited) {
      final converted = _convertedAmountInput(
        state: state,
        amountMinor: parsedAmountMinor,
        fromCurrency: txCurrency,
        toCurrency: counterAccount.currency,
      );
      _setConvertedDraft(
        controller: _counterAmountController,
        value: converted,
        updateDraft: (value) => _counterAmount = value,
        activeField: 2,
      );
    }
  }

  String _convertedAmountInput({
    required LedgerState state,
    required int amountMinor,
    required String fromCurrency,
    required String toCurrency,
  }) {
    final converted = convertMoneyForDisplay(
      state,
      Money(amountMinor: amountMinor, currency: fromCurrency),
      toCurrency,
    );
    return _formatAmountInput(converted.amountMinor);
  }

  void _setConvertedDraft({
    required TextEditingController controller,
    required String value,
    required ValueChanged<String> updateDraft,
    required int activeField,
  }) {
    if (controller.text != value) controller.text = value;
    if (_activeField != activeField) updateDraft(value);
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _saveRecord() async {
    final state = ref.read(ledgerProvider);
    final editingTransaction = widget.transactionId == null
        ? null
        : state.transactions.firstWhereOrNull(
            (transaction) => transaction.id == widget.transactionId,
          );
    // Evaluate any pending expression before saving
    final resolvedAmount = _expression.isNotEmpty
        ? _evaluate('$_expression ${_amount.isEmpty ? "0" : _amount}')
        : _amount;
    final parsedAmountMinor = _amountMinorFromInput(resolvedAmount);

    final txCurrency =
        _transactionCurrency ??
        accountById(state, _accountId)?.currency ??
        state.preferences.baseCurrency;
    final sourceAcc = accountById(state, _accountId);
    final isForeign =
        txCurrency.toUpperCase() !=
        (sourceAcc?.currency.toUpperCase() ??
            state.preferences.baseCurrency.toUpperCase());
    final counterAcc = accountById(state, _counterAccountId);
    final isCrossTransfer =
        _type == 'transfer' &&
        counterAcc != null &&
        counterAcc.currency.toUpperCase() !=
            (sourceAcc?.currency.toUpperCase() ??
                state.preferences.baseCurrency.toUpperCase());

    int finalAmountMinor = parsedAmountMinor;
    int? finalOriginalAmountMinor;
    String? finalOriginalCurrency;
    int? finalCounterAmountMinor;

    if (isForeign) {
      finalOriginalAmountMinor = parsedAmountMinor;
      finalOriginalCurrency = txCurrency;
      if (_localAmountController.text.trim().isNotEmpty) {
        finalAmountMinor = _amountMinorFromInput(
          _localAmountController.text.trim(),
        );
      } else {
        finalAmountMinor = convertMoneyForDisplay(
          state,
          Money(amountMinor: parsedAmountMinor, currency: txCurrency),
          sourceAcc?.currency ?? state.preferences.baseCurrency,
        ).amountMinor;
      }
    }

    if (isCrossTransfer) {
      if (_counterAmountController.text.trim().isNotEmpty) {
        finalCounterAmountMinor = _amountMinorFromInput(
          _counterAmountController.text.trim(),
        );
      } else {
        final counterCurrency = counterAcc.currency;
        final txAmount = Money(
          amountMinor: parsedAmountMinor,
          currency: txCurrency,
        );
        finalCounterAmountMinor = convertMoneyForDisplay(
          state,
          txAmount,
          counterCurrency,
        ).amountMinor;
      }
    }

    final account = accountById(state, _accountId);
    if (account == null) {
      _showMessage('Choose an account before saving.');
      return;
    }
    if (finalAmountMinor == 0 && parsedAmountMinor == 0) {
      _showMessage('Enter an amount before saving.');
      return;
    }
    if (_type == 'transfer' && _counterAccountId == null) {
      _showMessage('Choose a destination account for this transfer.');
      return;
    }
    final selectedCategory = categoryById(state, _categoryId);
    final needsCategory = _type != 'transfer';
    if (needsCategory &&
      (selectedCategory == null || selectedCategory.isArchived)) {
      _showMessage('Choose a category before saving.');
      return;
    }
    try {
      final savedTx = await ref
          .read(ledgerProvider.notifier)
          .upsertTransaction(
            id: editingTransaction?.id,
            type: _type,
            accountId: account.id,
            counterAccountId: _counterAccountId,
            amountMinor: finalAmountMinor,
            originalAmountMinor: finalOriginalAmountMinor,
            originalCurrency: finalOriginalCurrency,
            counterAmountMinor: finalCounterAmountMinor,
            categoryId: _type == 'transfer' ? null : selectedCategory!.id,
            status: editingTransaction?.status ?? 'cleared',
            source: editingTransaction?.source ?? 'manual',
            paymentMethod: _paymentMethodController.text.trim().isEmpty
                ? null
                : _paymentMethodController.text.trim(),
            notes: _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            occurredAt: _occurredAt,
          );

      for (final charge in _charges) {
        final amountInput = charge.amountController.text.trim();
        final chargeAmountMinor = _amountMinorFromInput(amountInput);
        if (chargeAmountMinor > 0) {
          await ref
              .read(ledgerProvider.notifier)
              .upsertTransaction(
                type: 'expense',
                accountId: account.id,
                amountMinor: chargeAmountMinor,
                notes: charge.labelController.text.trim().isEmpty
                    ? null
                    : charge.labelController.text.trim(),
                categoryId: null,
                occurredAt: _occurredAt,
                originalTransactionId: savedTx.id,
              );
        }
      }
      if (!mounted) return;
      _showMessage(
        editingTransaction == null
            ? 'Record saved to your local ledger.'
            : 'Record updated in your local ledger.',
      );
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/');
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage(error.toString());
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  void _syncEditDraft(TransactionRecord? transaction, LedgerState state) {
    final key = transaction?.id ?? '__new__';
    if (_loadedTransactionId == key) return;
    _loadedTransactionId = key;
    if (transaction == null) {
      _type = 'expense';
      _amount = '0';
      _expression = '';
      _transactionCurrency = null;
      _accountId = _initialAccountId(state);
      _counterAccountId = null;
      _categoryId = null;
      _localAmount = '';
      _localExpression = '';
      _counterAmount = '';
      _counterExpression = '';
      _localAmountController.text = '';
      _counterAmountController.text = '';
      _localAmountEdited = false;
      _counterAmountEdited = false;
      _notesController.text = '';
      _locationController.text = '';
      _paymentMethodController.text = '';
      return;
    }
    _type = transaction.type;
    _amount = _formatAmountInput(
      (transaction.originalAmount ?? transaction.amount).amountMinor,
    );
    _transactionCurrency =
        transaction.originalAmount?.currency ?? transaction.amount.currency;
    if (transaction.originalAmount != null) {
      _localAmountController.text = _formatAmountInput(
        transaction.amount.amountMinor,
      );
      _localAmountEdited = true;
    } else {
      _localAmountEdited = false;
    }
    if (transaction.counterAmount != null &&
        transaction.counterAmount?.currency != transaction.amount.currency) {
      _counterAmountController.text = _formatAmountInput(
        transaction.counterAmount!.amountMinor,
      );
      _counterAmountEdited = true;
    } else {
      _counterAmountEdited = false;
    }
    _expression = '';
    _accountId = transaction.accountId;
    _counterAccountId = transaction.counterAccountId;
    _categoryId = transaction.categoryId;
    _notesController.text = transaction.notes ?? '';
    _locationController.text = transaction.locationLabel ?? '';
    _paymentMethodController.text = transaction.paymentMethod ?? '';
    _occurredAt = transaction.occurredAt;
  }

  void _syncCreateDraftAccount(
    LedgerState state,
    TransactionRecord? editingTransaction,
  ) {
    if (editingTransaction != null) return;
    final currentAccount = accountById(state, _accountId);
    if (_accountId != null &&
        (currentAccount == null || currentAccount.isArchived)) {
      _accountId = null;
    }
    if (_accountId != null) return;
    _accountId = _initialAccountId(state);
  }

  String? _initialAccountId(LedgerState state) {
    final initialAccount = accountById(state, widget.initialAccountId);
    if (initialAccount == null || initialAccount.isArchived) return null;
    return initialAccount.id;
  }

  void _clearInvalidCategory(
    LedgerState state,
    TransactionRecord? editingTransaction,
  ) {
    if (editingTransaction != null) return;
    if (_type == 'transfer') {
      _categoryId = null;
      return;
    }
    final selectedCategory = categoryById(state, _categoryId);
    if (selectedCategory == null ||
        selectedCategory.isArchived) {
      _categoryId = null;
    }
  }
}

// ── Helper types ──────────────────────────────────────────────────────────────

class _FxAmountPanel extends StatelessWidget {
  const _FxAmountPanel({
    required this.state,
    required this.sourceAccount,
    required this.counterAccount,
    required this.txCurrency,
    required this.isForeign,
    required this.isCrossTransfer,
    required this.sentAmount,
    required this.localAmount,
    required this.counterAmount,
    required this.activeField,
    required this.onEditMain,
    required this.onEditLocal,
    required this.onEditCounter,
  });

  final LedgerState state;
  final Account? sourceAccount;
  final Account? counterAccount;
  final String txCurrency;
  final bool isForeign;
  final bool isCrossTransfer;
  final String sentAmount;
  final String localAmount;
  final String counterAmount;
  final int activeField;
  final VoidCallback onEditMain;
  final VoidCallback onEditLocal;
  final VoidCallback onEditCounter;

  @override
  Widget build(BuildContext context) {
    final sourceCurrency = sourceAccount?.currency ?? state.preferences.baseCurrency;
    final counterCurrency = counterAccount?.currency;
    final rateLabel = counterCurrency == null
        ? null
        : _fxRateLabel(state, txCurrency, counterCurrency);

    if (isCrossTransfer && counterAccount != null) {
      return Row(
        children: [
          Expanded(
            child: _FxAmountCard(
              title: 'Sent',
              subtitle: sourceAccount?.name ?? sourceCurrency,
              amount: sentAmount,
              currency: txCurrency,
              icon: Icons.upload_rounded,
              selected: activeField == 0,
              onTap: onEditMain,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _FxAmountCard(
              title: 'Received',
              subtitle: rateLabel ?? counterAccount!.name,
              amount: counterAmount,
              currency: counterAccount!.currency,
              icon: Icons.download_rounded,
              selected: activeField == 2,
              onTap: onEditCounter,
            ),
          ),
        ],
      );
    }

    if (isForeign && sourceAccount != null) {
      return Row(
        children: [
          Expanded(
            child: _FxAmountCard(
              title: 'Original',
              subtitle: 'Transaction amount',
              amount: sentAmount,
              currency: txCurrency,
              icon: Icons.receipt_long_outlined,
              selected: activeField == 0,
              onTap: onEditMain,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _FxAmountCard(
              title: 'Charged',
              subtitle: _fxRateLabel(state, txCurrency, sourceCurrency) ?? sourceAccount!.name,
              amount: localAmount,
              currency: sourceCurrency,
              icon: Icons.currency_exchange_rounded,
              selected: activeField == 1,
              onTap: onEditLocal,
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

class _FxAmountCard extends StatelessWidget {
  const _FxAmountCard({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.currency,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String amount;
  final String currency;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Material(
      color: selected
          ? scheme.primaryContainer.withAlpha(110)
          : scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          constraints: const BoxConstraints(minHeight: 78),
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: color),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${amount.isEmpty ? '0' : amount} $currency',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _fxRateLabel(LedgerState state, String from, String to) {
  final rate = rateBetween(state, from, to);
  if (rate == null || rate <= 0 || !rate.isFinite) return null;
  final displayRate = rate >= 1 ? rate.toStringAsFixed(2) : rate.toStringAsFixed(4);
  return '1 ${from.toUpperCase()} ≈ $displayRate ${to.toUpperCase()}';
}

class _CalcState {
  const _CalcState({required this.amount, required this.expression});
  final String amount;
  final String expression;
}

class _ChargeDraft {
  _ChargeDraft({
    required this.id,
    required this.labelController,
    required this.amountController,
  });
  final String id;
  final TextEditingController labelController;
  final TextEditingController amountController;

  void dispose() {
    labelController.dispose();
    amountController.dispose();
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

// ── Pure helper functions ─────────────────────────────────────────────────────

Color _toneColor(BuildContext context, String type) {
  final scheme = Theme.of(context).colorScheme;
  return switch (type) {
    'income' =>
      Theme.of(context).brightness == Brightness.dark
          ? AppColors.positiveDark
          : AppColors.positiveLight,
    'transfer' => scheme.primary,
    _ => scheme.error,
  };
}

int _amountMinorFromInput(String value) {
  final normalized = value.replaceAll(',', '').trim();
  final parsed = double.tryParse(normalized) ?? 0;
  return (parsed * 100).round();
}

String _formatAmountInput(int amountMinor) {
  final amount = amountMinor / 100;
  if (amount == amount.roundToDouble()) return amount.round().toString();
  return amount.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
}

String _trimNumber(double value) {
  if (!value.isFinite) return '0';
  final rounded = (value * 100).round() / 100;
  return rounded.toString().replaceAll(RegExp(r'\.0$'), '');
}

String _amountWords(String value) {
  final parsed = double.tryParse(value.replaceAll(',', '')) ?? 0;
  if (parsed == 0) return '0';
  final format = NumberFormat.currency(locale: 'en_IN', symbol: '');
  String formatted = format.format(parsed).trim();
  if (formatted.endsWith('.00')) {
    formatted = formatted.substring(0, formatted.length - 3);
  }
  return formatted;
}

extension _FirstWhereOrNull<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}
