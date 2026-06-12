import 'dart:async';

import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../capture/message_parser.dart';
import '../features/capture/sms_spooler.dart';
import '../imports/wallet_csv_parser.dart';
import '../ledger/ledger_selectors.dart';
import 'ledger_archive.dart';
import 'ledger_codec.dart';
import 'ledger_defaults.dart';
import 'ledger_models.dart';

const _ledgerStorageKey = 'one_wallet_flutter.ledger.v1';

final ledgerRepositoryProvider = Provider<LedgerRepository>((ref) {
  return const LedgerRepository();
});

final ledgerLoadStateProvider = StateProvider<LedgerLoadState>((ref) {
  return const LedgerLoadState.loading();
});

final ledgerProvider = StateNotifierProvider<LedgerController, LedgerState>((
  ref,
) {
  return LedgerController(
    ref.watch(ledgerRepositoryProvider),
    setLoadState: (next) =>
        ref.read(ledgerLoadStateProvider.notifier).state = next,
    initialState: emptyLedgerState(),
  );
});

class LedgerLoadState {
  const LedgerLoadState._({
    required this.isReady,
    this.hasPersistedLedger = false,
    this.errorMessage,
  });

  const LedgerLoadState.loading()
    : this._(isReady: false, hasPersistedLedger: false);

  const LedgerLoadState.ready({required bool hasPersistedLedger})
    : this._(isReady: true, hasPersistedLedger: hasPersistedLedger);

  const LedgerLoadState.failed(String message)
    : this._(isReady: true, errorMessage: message);

  final bool isReady;
  final bool hasPersistedLedger;
  final String? errorMessage;
}

class LedgerRepository {
  const LedgerRepository();

  Future<LedgerState?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final payload = preferences.getString(_ledgerStorageKey);
    if (payload == null || payload.trim().isEmpty) return null;
    return await foundation.compute(decodeLedgerState, payload);
  }

  Future<void> save(LedgerState state) async {
    final preferences = await SharedPreferences.getInstance();
    final payload = await foundation.compute(encodeLedgerState, state);
    await preferences.setString(_ledgerStorageKey, payload);
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_ledgerStorageKey);
  }
}

class LedgerController extends StateNotifier<LedgerState> {
  LedgerController(
    this._repository, {
    void Function(LedgerLoadState)? setLoadState,
    LedgerState? initialState,
  }) : _setLoadState = setLoadState ?? _ignoreLoadState,
       super(initialState ?? emptyLedgerState()) {
    unawaited(_loadPersistedLedger());
  }

  final LedgerRepository _repository;
  final void Function(LedgerLoadState) _setLoadState;

  Future<void> _loadPersistedLedger() async {
    try {
      final restored = await _repository.load();
      if (!mounted) return;
      if (restored != null) {
        final fixed = _fixStaleScheduledTransactions(restored);
        state = fixed;
        if (!identical(fixed, restored)) {
          unawaited(_repository.save(fixed));
        }
      }
      _setLoadState(
        LedgerLoadState.ready(hasPersistedLedger: restored != null),
      );
      unawaited(processSpooledSms());
    } catch (error) {
      if (!mounted) return;
      _setLoadState(
        LedgerLoadState.failed('Unable to restore local wallet: $error'),
      );
    }
  }

  LedgerState _fixStaleScheduledTransactions(LedgerState ledger) {
    bool changed = false;
    final updated = ledger.transactions.map((scheduled) {
      if (scheduled.status != 'scheduled') return scheduled;
      
      final history = ledger.transactions
          .where((t) => t.originalTransactionId == scheduled.id && t.status != 'scheduled' && t.status != 'void')
          .toList();
      
      if (history.isEmpty) return scheduled;
      
      history.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      final latest = history.first;
      
      if (scheduled.occurredAt.isBefore(latest.occurredAt) || scheduled.occurredAt.isAtSameMomentAs(latest.occurredAt)) {
        changed = true;
        DateTime nextDate = scheduled.occurredAt;
        final freq = scheduled.recurrenceFrequency ?? 'monthly';
        
        while (nextDate.isBefore(latest.occurredAt) || nextDate.isAtSameMomentAs(latest.occurredAt)) {
           switch (freq.toLowerCase()) {
            case 'daily':
              nextDate = nextDate.add(const Duration(days: 1));
              break;
            case 'weekly':
              nextDate = nextDate.add(const Duration(days: 7));
              break;
            case 'monthly':
              var year = nextDate.year;
              var month = nextDate.month + 1;
              if (month > 12) { year++; month -= 12; }
              var day = nextDate.day;
              final daysInNextMonth = DateTime(year, month + 1, 0).day;
              if (day > daysInNextMonth) day = daysInNextMonth;
              nextDate = DateTime(year, month, day, nextDate.hour, nextDate.minute, nextDate.second);
              break;
            case 'yearly':
              var year = nextDate.year + 1;
              var month = nextDate.month;
              var day = nextDate.day;
              final daysInNextMonth = DateTime(year, month + 1, 0).day;
              if (day > daysInNextMonth) day = daysInNextMonth;
              nextDate = DateTime(year, month, day, nextDate.hour, nextDate.minute, nextDate.second);
              break;
            default:
              var year = nextDate.year;
              var month = nextDate.month + 1;
              if (month > 12) { year++; month -= 12; }
              var day = nextDate.day;
              final daysInNextMonth = DateTime(year, month + 1, 0).day;
              if (day > daysInNextMonth) day = daysInNextMonth;
              nextDate = DateTime(year, month, day, nextDate.hour, nextDate.minute, nextDate.second);
              break;
          }
        }
        return scheduled.copyWith(occurredAt: nextDate);
      }
      return scheduled;
    }).toList();
    
    if (!changed) return ledger;
    return ledger.copyWith(transactions: updated);
  }

  Future<void> clearLocalWallet({String userId = 'local-user'}) async {
    final next = emptyLedgerState(userId: userId);
    state = next;
    await _repository.clear();
  }

  Future<void> processSpooledSms() async {
    try {
      final spooled = await SmsSpooler.popSpooledMessages();
      if (spooled.isEmpty) return;
      
      for (final payload in spooled) {
        final body = payload['body'] as String?;
        if (body != null && body.isNotEmpty) {
          await importSmsMessage(body);
        }
      }
    } catch (e) {
      debugPrint('Error processing spooled SMS: $e');
    }
  }

  Future<void> createStarterWallet({
    required String userId,
    required String accountName,
    required String currency,
    required Color accountColor,
    String accountType = 'bank',
    int openingBalanceMinor = 0,
  }) async {
    if (_hasWalletData(state)) {
      return;
    }

    final normalizedCurrency = currency.trim().toUpperCase().isEmpty
        ? 'INR'
        : currency.trim().toUpperCase();
    final preferences = LedgerPreferences(
      baseCurrency: normalizedCurrency,
      displayCurrency: normalizedCurrency,
      enabledCurrencies: [normalizedCurrency],
      locale: normalizedCurrency == 'INR' ? 'en_IN' : 'en_US',
    );
    final starter = emptyLedgerState(userId: userId, preferences: preferences);
    final account = Account(
      id: _newId('acc'),
      name: accountName.trim().isEmpty
          ? '$normalizedCurrency account'
          : accountName.trim(),
      type: accountType,
      currency: normalizedCurrency,
      openingBalance: Money(
        amountMinor: openingBalanceMinor,
        currency: normalizedCurrency,
      ),
      color: accountColor,
      sortOrder: 1,
    );
    await _commit(starter.copyWith(accounts: [account]));
  }

  String exportArchive({String source = 'flutter-local'}) {
    return encodeLedgerArchive(state, source: source);
  }

  Future<void> importArchive(String archiveSource) async {
    await _commit(decodeLedgerArchive(archiveSource));
  }

  Future<void> restoreLedgerState(LedgerState next) async {
    await _commit(next.copyWith(version: currentLedgerStateVersion));
  }

  Future<void> setHomeWidgetPreferences({
    List<String>? order,
    List<String>? hidden,
    Map<String, String>? sizes,
    Map<String, String>? filters,
  }) async {
    final preferences = state.preferences;
    await _commit(
      state.copyWith(
        preferences: preferences.copyWith(
          homeWidgetOrder: _normalizeStringList(
            order ?? preferences.homeWidgetOrder,
          ),
          homeWidgetHidden: _normalizeStringList(
            hidden ?? preferences.homeWidgetHidden,
          ),
          homeWidgetSizes: _normalizeStringMap(
            sizes ?? preferences.homeWidgetSizes,
          ),
          homeWidgetFilters: _normalizeStringMap(
            filters ?? preferences.homeWidgetFilters,
          ),
        ),
      ),
    );
  }

  Future<void> setHomeWidgetOrder(List<String> order) async {
    await setHomeWidgetPreferences(order: order);
  }

  Future<void> setHomeWidgetFilter(String widgetId, String? preset) async {
    final key = widgetId.trim();
    if (key.isEmpty) return;
    final nextFilters = Map<String, String>.from(
      state.preferences.homeWidgetFilters,
    );
    final value = preset?.trim();
    if (value == null || value.isEmpty) {
      nextFilters.remove(key);
    } else {
      nextFilters[key] = value;
    }
    await setHomeWidgetPreferences(filters: nextFilters);
  }

  Future<void> resetHomeWidgetOrder() async {
    const defaults = LedgerPreferences();
    await _commit(
      state.copyWith(
        preferences: state.preferences.copyWith(
          homeWidgetOrder: defaults.homeWidgetOrder,
          homeWidgetHidden: defaults.homeWidgetHidden,
          homeWidgetSizes: defaults.homeWidgetSizes,
          homeWidgetFilters: defaults.homeWidgetFilters,
        ),
      ),
    );
  }

  Future<void> setLocale(String locale) async {
    await _commit(
      state.copyWith(preferences: state.preferences.copyWith(locale: locale)),
    );
  }



  Future<void> setStartDayOfMonth(int day) async {
    await _commit(
      state.copyWith(
        preferences: state.preferences.copyWith(startDayOfMonth: day),
      ),
    );
  }

  Future<void> resetLedger() async {
    await clearLocalWallet(userId: state.userId);
  }

  Future<void> setDisplayCurrency(String currency) async {
    final normalized = currency.trim().toUpperCase();
    if (normalized.isEmpty) return;
    final enabled = <String>{
      ...state.preferences.enabledCurrencies.map(
        (value) => value.toUpperCase(),
      ),
      state.preferences.baseCurrency.toUpperCase(),
      normalized,
    }.toList()..sort();
    await _commit(
      state.copyWith(
        preferences: state.preferences.copyWith(
          displayCurrency: normalized,
          enabledCurrencies: enabled,
        ),
      ),
    );
  }

  Future<void> addTransaction({
    required String type,
    required String accountId,
    required int amountMinor,
    String status = 'cleared',
    String source = 'manual',
    String? counterAccountId,
    String? categoryId,
    String? paymentMethod,
    String? notes,
    DateTime? occurredAt,
  }) async {
    await upsertTransaction(
      type: type,
      accountId: accountId,
      amountMinor: amountMinor,
      status: status,
      source: source,
      counterAccountId: counterAccountId,
      categoryId: categoryId,
      paymentMethod: paymentMethod,
      notes: notes,
      occurredAt: occurredAt,
    );
  }

  Future<TransactionRecord> upsertTransaction({
    String? id,
    required String type,
    required String accountId,
    required int amountMinor,
    String status = 'cleared',
    String source = 'manual',
    String? counterAccountId,
    int? counterAmountMinor,
    int? originalAmountMinor,
    String? originalCurrency,
    String? categoryId,
    String? paymentMethod,
    String? notes,
    DateTime? occurredAt,
    String? recurrenceFrequency,
    bool? isExcludedFromReports,
    String? originalTransactionId,
  }) async {
    final sourceAccount = accountById(state, accountId);
    if (sourceAccount == null) {
      throw StateError('Choose an account before saving.');
    }
    final existing = id == null ? null : _transactionById(state, id);
    final counterAccount = accountById(state, counterAccountId);
    final effectiveAmountMinor = type == 'adjustment'
        ? amountMinor
        : amountMinor.abs();
    final amount = Money(
      amountMinor: effectiveAmountMinor,
      currency: sourceAccount.currency,
    );
    final baseAmount = convertMoneyForDisplay(state, amount, state.preferences.baseCurrency);
    
    Money? originalAmount;
    if (originalAmountMinor != null && originalCurrency != null && originalCurrency.toUpperCase() != sourceAccount.currency.toUpperCase()) {
      originalAmount = Money(amountMinor: originalAmountMinor, currency: originalCurrency.toUpperCase());
    } else {
      originalAmount = existing?.originalAmount;
    }
    
    Money? counterAmount;
    if (counterAccount != null) {
      if (counterAmountMinor != null) {
        counterAmount = Money(amountMinor: counterAmountMinor, currency: counterAccount.currency);
      } else if (counterAccount.currency.toUpperCase() == sourceAccount.currency.toUpperCase()) {
        counterAmount = amount;
      } else {
        counterAmount = convertMoneyForDisplay(state, amount, counterAccount.currency);
      }
    }

    double? fxRate = existing?.fxRate;
    if (counterAmount != null && counterAmount.currency.toUpperCase() != amount.currency.toUpperCase() && amount.amountMinor != 0) {
      fxRate = counterAmount.amountMinor / amount.amountMinor;
    }
    
    double? originalFxRate = existing?.originalFxRate;
    if (originalAmount != null && originalAmount.currency.toUpperCase() != amount.currency.toUpperCase() && originalAmount.amountMinor != 0) {
      originalFxRate = amount.amountMinor / originalAmount.amountMinor;
    }

    final transaction = TransactionRecord(
      id: existing?.id ?? id ?? _newId('tx'),
      type: type,
      status: status,
      source: source,
      accountId: sourceAccount.id,
      counterAccountId: counterAccount?.id,
      amount: amount,
      baseAmount: baseAmount,
      counterAmount: counterAmount,
      originalAmount: originalAmount,
      fxRate: fxRate,
      originalFxRate: originalFxRate,
      categoryId: type == 'transfer' || type == 'adjustment'
          ? null
          : categoryId,
      locationLabel: existing?.locationLabel,
      paymentMethod: _blankToNull(paymentMethod),
      notes: _blankToNull(notes),
      importBatchId: existing?.importBatchId,
      occurredAt: occurredAt ?? existing?.occurredAt ?? DateTime.now(),
      recurrenceFrequency: recurrenceFrequency ?? existing?.recurrenceFrequency,
      attachments: existing?.attachments ?? const [],
      isReimbursable: existing?.isReimbursable ?? false,
      isTaxDeductible: existing?.isTaxDeductible ?? false,
      isExcludedFromReports:
          isExcludedFromReports ?? existing?.isExcludedFromReports ?? false,
      sourceConfidence: existing?.sourceConfidence,
      externalRef: existing?.externalRef,
      originalTransactionId: originalTransactionId ?? existing?.originalTransactionId,
    );
    final transactions = [...state.transactions];
    final index = transactions.indexWhere((item) => item.id == transaction.id);
    if (index == -1) {
      transactions.insert(0, transaction);
    } else {
      transactions[index] = transaction;
    }
    await _commit(state.copyWith(transactions: transactions));
    return transaction;
  }

  Future<TransactionRecord> updateTransactionStatus(
    String id,
    String status, {
    DateTime? occurredAt,
  }) async {
    final existing = _transactionById(state, id);
    if (existing == null) throw StateError('Transaction not found.');
    return upsertTransaction(
      id: existing.id,
      type: existing.type,
      accountId: existing.accountId,
      amountMinor: existing.amount.amountMinor,
      status: status,
      source: existing.source,
      counterAccountId: existing.counterAccountId,
      categoryId: existing.categoryId,
      paymentMethod: existing.paymentMethod,
      notes: existing.notes,
      occurredAt: occurredAt ?? existing.occurredAt,
      recurrenceFrequency: existing.recurrenceFrequency,
      isExcludedFromReports: existing.isExcludedFromReports,
    );
  }

  Future<TransactionRecord> postponeTransaction(
    String id,
    Duration duration,
  ) async {
    final existing = _transactionById(state, id);
    if (existing == null) throw StateError('Transaction not found.');
    return updateTransactionStatus(
      id,
      existing.status,
      occurredAt: existing.occurredAt.add(duration),
    );
  }

  Future<void> deleteTransaction(String id) async {
    await _commit(
      state.copyWith(
        transactions: state.transactions
            .where((transaction) => transaction.id != id)
            .toList(),
      ),
    );
  }

  Future<void> addAttachment(String transactionId, TransactionAttachment attachment) async {
    final transactions = [...state.transactions];
    final index = transactions.indexWhere((item) => item.id == transactionId);
    if (index == -1) throw StateError('Transaction not found.');
    final existing = transactions[index];
    final updated = TransactionRecord(
      id: existing.id,
      type: existing.type,
      status: existing.status,
      source: existing.source,
      accountId: existing.accountId,
      counterAccountId: existing.counterAccountId,
      amount: existing.amount,
      baseAmount: existing.baseAmount,
      counterAmount: existing.counterAmount,
      originalAmount: existing.originalAmount,
      fxRate: existing.fxRate,
      originalFxRate: existing.originalFxRate,
      categoryId: existing.categoryId,
      locationLabel: existing.locationLabel,
      paymentMethod: existing.paymentMethod,
      notes: existing.notes,
      importBatchId: existing.importBatchId,
      occurredAt: existing.occurredAt,
      recurrenceFrequency: existing.recurrenceFrequency,
      attachments: [...existing.attachments, attachment],
      isReimbursable: existing.isReimbursable,
      isTaxDeductible: existing.isTaxDeductible,
      isExcludedFromReports: existing.isExcludedFromReports,
      sourceConfidence: existing.sourceConfidence,
      externalRef: existing.externalRef,
      originalTransactionId: existing.originalTransactionId,
    );
    transactions[index] = updated;
    await _commit(state.copyWith(transactions: transactions));
  }

  Future<Account> upsertAccount({
    String? id,
    required String name,
    required String type,
    required String currency,
    int? openingBalanceMinor,
    Color? color,
    String? institution,
    String? groupName,
    String? cardLast4,
    String? accountLast4,
    AccountLoanDetails? loanDetails,
    bool includeInTotals = true,
    bool includeInReports = true,
    bool includeInNetWorth = true,
    bool showOnHome = true,
    bool isArchived = false,
  }) async {
    final existing = accountById(state, id);
    final account = Account(
      id: existing?.id ?? id ?? _newId('acc'),
      name: name.trim().isEmpty ? 'New account' : name.trim(),
      type: type,
      currency: currency,
      openingBalance: openingBalanceMinor == null
          ? existing?.openingBalance ??
                Money(amountMinor: 0, currency: currency)
          : Money(amountMinor: openingBalanceMinor, currency: currency),
      color: color ?? existing?.color,
      institution: _blankToNull(institution),
      groupName: _blankToNull(groupName),
      cardLast4: _blankToNull(cardLast4),
      accountLast4: _blankToNull(accountLast4),
      loanDetails: loanDetails ?? existing?.loanDetails,
      includeInTotals: includeInTotals,
      includeInReports: includeInReports,
      includeInNetWorth: includeInNetWorth,
      showOnHome: showOnHome,
      isArchived: isArchived,
      sortOrder: existing?.sortOrder ?? state.accounts.length + 1,
    );

    final accounts = [...state.accounts];
    final index = accounts.indexWhere((item) => item.id == account.id);
    if (index == -1) {
      accounts.add(account);
    } else {
      accounts[index] = account;
    }
    await _commit(state.copyWith(accounts: accounts));
    return account;
  }

  Future<void> deleteAccount(String id) async {
    final isUsed = state.transactions.any(
      (transaction) =>
          transaction.accountId == id || transaction.counterAccountId == id,
    );
    if (isUsed) {
      final accounts = [
        for (final account in state.accounts)
          account.id == id ? account.copyWith(isArchived: true) : account,
      ];
      await _commit(state.copyWith(accounts: accounts));
      return;
    }
    await _commit(
      state.copyWith(
        accounts: state.accounts.where((account) => account.id != id).toList(),
      ),
    );
  }

  Future<void> reorderAccounts(List<String> orderedIds) async {
    final updated = <Account>[];
    for (final account in state.accounts) {
      final index = orderedIds.indexOf(account.id);
      updated.add(
        account.copyWith(
          sortOrder: index == -1 ? account.sortOrder : index,
        ),
      );
    }
    await _commit(state.copyWith(accounts: updated));
  }

  Future<void> upsertCategory({
    String? id,
    required String name,
    required String kind,
    String? parentId,
    bool isArchived = false,
  }) async {
    final existing = categoryById(state, id);
    final normalizedKind = kind == 'income' ? 'income' : 'expense';
    final category = Category(
      id: existing?.id ?? id ?? _newId('cat'),
      name: name.trim().isEmpty ? 'New category' : name.trim(),
      kind: normalizedKind,
      color: existing?.color,
      parentId: _blankToNull(parentId),
      isArchived: isArchived,
      sortOrder: existing?.sortOrder ?? state.categories.length + 1,
    );
    final categories = [...state.categories];
    final index = categories.indexWhere((item) => item.id == category.id);
    if (index == -1) {
      categories.add(category);
    } else {
      categories[index] = category;
    }
    await _commit(state.copyWith(categories: categories));
  }

  Future<void> archiveCategory(String id, {required bool archived}) async {
    final categories = [
      for (final category in state.categories)
        category.id == id ? category.copyWith(isArchived: archived) : category,
    ];
    await _commit(state.copyWith(categories: categories));
  }

  Future<void> updateCaptureCandidateStatus(String id, String status) async {
    final candidates = [
      for (final candidate in state.captureCandidates)
        candidate.id == id ? candidate.copyWith(status: status) : candidate,
    ];
    await _commit(state.copyWith(captureCandidates: candidates));
  }

  Future<void> clearCaptureCandidateWarnings(String id) async {
    final candidates = [
      for (final candidate in state.captureCandidates)
        candidate.id == id ? candidate.copyWith(warnings: const []) : candidate,
    ];
    await _commit(state.copyWith(captureCandidates: candidates));
  }

  Future<TransactionRecord> approveCaptureCandidate(String id) async {
    final candidate = _candidateById(state, id);
    if (candidate == null) {
      throw StateError('Capture candidate not found.');
    }
    if (candidate.parsedAmount == null) {
      throw StateError('Candidate has no parsed amount to post.');
    }
    final account =
        accountById(state, candidate.suggestedAccountId) ??
        state.accounts.where((account) => !account.isArchived).firstOrNull ??
        (state.accounts.isEmpty ? null : state.accounts.first);
    if (account == null) {
      throw StateError('Create an account before confirming captures.');
    }
    final type = candidate.transactionType == 'income' ? 'income' : 'expense';
    final category =
        categoryById(state, candidate.suggestedCategoryId) ??
        _matchCategory(state, candidate.merchant, type);
    final amount = candidate.parsedAmount!.copyWith(currency: account.currency);
    final transaction = TransactionRecord(
      id: _newId('cap-tx'),
      type: type,
      status: 'cleared',
      source: candidate.source,
      accountId: account.id,
      amount: amount,
      baseAmount: amount.copyWith(currency: state.preferences.baseCurrency),
      categoryId: category?.id,
      occurredAt: candidate.createdAt,
      paymentMethod: candidate.source.toUpperCase(),
      notes: _blankToNull(candidate.merchant) ?? candidate.rawText,
    );
    final candidates = [
      for (final item in state.captureCandidates)
        item.id == id ? item.copyWith(status: 'approved') : item,
    ];
    await _commit(
      state.copyWith(
        transactions: [transaction, ...state.transactions],
        captureCandidates: candidates,
      ),
    );
    return transaction;
  }

  Future<void> updateCaptureCandidateDetails({
    required String id,
    required Money? parsedAmount,
    required String? merchant,
    required String transactionType,
    required String? suggestedAccountId,
    required String? suggestedCategoryId,
  }) async {
    final candidates = [
      for (final candidate in state.captureCandidates)
        candidate.id == id
            ? CaptureCandidate(
                id: candidate.id,
                source: candidate.source,
                status: candidate.status,
                createdAt: candidate.createdAt,
                rawText: candidate.rawText,
                parsedAmount: parsedAmount,
                merchant: _blankToNull(merchant),
                transactionType: transactionType == 'income'
                    ? 'income'
                    : 'expense',
                suggestedAccountId: _blankToNull(suggestedAccountId),
                suggestedCategoryId: _blankToNull(suggestedCategoryId),
                warnings: candidate.warnings,
              )
            : candidate,
    ];
    await _commit(state.copyWith(captureCandidates: candidates));
  }

  Future<CaptureCandidate?> importSmsMessage(String rawText) async {
    final parsed = parseTransactionMessage(
      rawText,
      fallbackCurrency: state.preferences.baseCurrency,
    );
    if (parsed.ignored) return null;

    String? matchedAccountId;
    if (parsed.last4 != null) {
      for (final account in state.accounts) {
        if (!account.isArchived && 
            (account.cardLast4 == parsed.last4 || account.accountLast4 == parsed.last4)) {
          matchedAccountId = account.id;
          break;
        }
      }
    }

    final candidate = CaptureCandidate(
      id: _newId('cap'),
      source: 'sms',
      status: 'pending',
      createdAt: DateTime.now(),
      rawText: parsed.rawText,
      parsedAmount: parsed.amount,
      merchant: parsed.merchant,
      transactionType: parsed.transactionType,
      suggestedAccountId: matchedAccountId ?? state.accounts
          .where((account) => !account.isArchived)
          .firstOrNull
          ?.id,
      suggestedCategoryId: _matchCategory(
        state,
        parsed.merchant,
        parsed.transactionType ?? 'expense',
      )?.id,
      warnings: parsed.warnings,
    );
    await _commit(
      state.copyWith(
        captureCandidates: [candidate, ...state.captureCandidates],
      ),
    );
    return candidate;
  }

  Future<int> importWalletCsvRows(List<ParsedWalletCsvRow> rows) async {
    if (rows.isEmpty) return 0;
    if (state.accounts.isEmpty) {
      throw StateError('Create an account before importing CSV rows.');
    }
    final batchId = _newId('import');
    final imported = <TransactionRecord>[];
    var duplicateCount = 0;
    final seenSignatures = {
      for (final transaction in state.transactions)
        _transactionSignature(transaction),
    };
    for (final row in rows) {
      final account =
          _matchAccount(state, row.accountName) ?? state.accounts.first;
      final category = _matchCategory(state, row.categoryName, row.type);
      final amount = row.amount.copyWith(currency: account.currency);
      final signature = _rowSignature(row, account.id, category?.id);
      if (seenSignatures.contains(signature)) {
        duplicateCount++;
        continue;
      }
      seenSignatures.add(signature);
      imported.add(
        TransactionRecord(
          id: _newId('csv'),
          type: row.type,
          status: 'cleared',
          source: 'import',
          accountId: account.id,
          amount: amount,
          baseAmount: amount.copyWith(currency: state.preferences.baseCurrency),
          categoryId: category?.id,
          occurredAt: row.occurredAt ?? DateTime.now(),
          notes: _blankToNull(row.notes) ?? 'Imported CSV row ${row.rowNumber}',
          importBatchId: batchId,
        ),
      );
    }
    final batch = ImportBatch(
      id: batchId,
      source: 'wallet_csv',
      status: 'posted',
      createdAt: DateTime.now(),
      rowCount: rows.length,
      importedCount: imported.length,
      duplicateCount: duplicateCount,
      warningCount: rows.fold<int>(0, (sum, row) => sum + row.warnings.length),
    );
    await _commit(
      state.copyWith(
        transactions: [...imported, ...state.transactions],
        importBatches: [batch, ...state.importBatches],
      ),
    );
    return imported.length;
  }

  Future<int> rollbackImportBatch(String batchId) async {
    final batch = _importBatchById(state, batchId);
    if (batch == null) throw StateError('Import batch not found.');
    if (batch.status == 'rolled_back') return 0;
    final beforeCount = state.transactions.length;
    final transactions = state.transactions
        .where((transaction) => transaction.importBatchId != batchId)
        .toList();
    final removed = beforeCount - transactions.length;
    final batches = [
      for (final item in state.importBatches)
        item.id == batchId ? item.copyWith(status: 'rolled_back') : item,
    ];
    await _commit(
      state.copyWith(transactions: transactions, importBatches: batches),
    );
    return removed;
  }

  Future<void> addBudget({
    required String name,
    required int amountMinor,
    String? currency,
  }) async {
    final budget = Budget(
      id: _newId('budget'),
      name: name.trim().isEmpty ? 'New budget' : name.trim(),
      amount: Money(
        amountMinor: amountMinor.abs(),
        currency: currency ?? state.preferences.baseCurrency,
      ),
      spent: Money(
        amountMinor: 0,
        currency: currency ?? state.preferences.baseCurrency,
      ),
    );
    await _commit(state.copyWith(budgets: [budget, ...state.budgets]));
  }

  Future<void> addGoal({
    required String name,
    required int targetMinor,
    String? currency,
  }) async {
    final goal = Goal(
      id: _newId('goal'),
      name: name.trim().isEmpty ? 'New goal' : name.trim(),
      target: Money(
        amountMinor: targetMinor.abs(),
        currency: currency ?? state.preferences.baseCurrency,
      ),
      saved: Money(
        amountMinor: 0,
        currency: currency ?? state.preferences.baseCurrency,
      ),
    );
    await _commit(state.copyWith(goals: [goal, ...state.goals]));
  }

  Future<void> _commit(LedgerState next) async {
    state = next;
    await _repository.save(next);
  }
}

bool _hasWalletData(LedgerState ledger) {
  return ledger.accounts.isNotEmpty ||
      ledger.transactions.isNotEmpty ||
      ledger.captureCandidates.isNotEmpty ||
      ledger.importBatches.isNotEmpty ||
      ledger.budgets.isNotEmpty ||
      ledger.goals.isNotEmpty;
}

String _newId(String prefix) {
  return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
}

String? _blankToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

List<String> _normalizeStringList(Iterable<String> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isEmpty || seen.contains(trimmed)) continue;
    seen.add(trimmed);
    result.add(trimmed);
  }
  return result;
}

Map<String, String> _normalizeStringMap(Map<String, String> values) {
  final result = <String, String>{};
  for (final entry in values.entries) {
    final key = entry.key.trim();
    final value = entry.value.trim();
    if (key.isEmpty || value.isEmpty) continue;
    result[key] = value;
  }
  return result;
}

TransactionRecord? _transactionById(LedgerState state, String id) {
  for (final transaction in state.transactions) {
    if (transaction.id == id) return transaction;
  }
  return null;
}

CaptureCandidate? _candidateById(LedgerState state, String id) {
  for (final candidate in state.captureCandidates) {
    if (candidate.id == id) return candidate;
  }
  return null;
}

ImportBatch? _importBatchById(LedgerState state, String id) {
  for (final batch in state.importBatches) {
    if (batch.id == id) return batch;
  }
  return null;
}

Account? _matchAccount(LedgerState state, String name) {
  final normalized = name.trim().toLowerCase();
  if (normalized.isEmpty) return null;
  for (final account in state.accounts) {
    if (account.name.toLowerCase() == normalized) return account;
  }
  for (final account in state.accounts) {
    if (account.name.toLowerCase().contains(normalized) ||
        normalized.contains(account.name.toLowerCase())) {
      return account;
    }
  }
  return null;
}

Category? _matchCategory(LedgerState state, String? name, String kind) {
  final normalized = name?.trim().toLowerCase();
  if (normalized != null && normalized.isNotEmpty) {
    for (final category in state.categories) {
      if (category.name.toLowerCase() == normalized) return category;
    }
    
    String? guessedKind;
    if (RegExp(r'\b(zomato|swiggy|food|restaurant|cafe|dining|mcdonalds|starbucks)\b').hasMatch(normalized)) {
      guessedKind = 'food';
    } else if (RegExp(r'\b(uber|ola|rapido|taxi|transit|metro|train|flight)\b').hasMatch(normalized)) {
      guessedKind = 'transport';
    } else if (RegExp(r'\b(amazon|flipkart|myntra|shopping)\b').hasMatch(normalized)) {
      guessedKind = 'shopping';
    } else if (RegExp(r'\b(netflix|spotify|prime|hotstar|subscription|movie)\b').hasMatch(normalized)) {
      guessedKind = 'entertainment';
    } else if (RegExp(r'\b(hospital|pharmacy|clinic|medical|health|doctor)\b').hasMatch(normalized)) {
      guessedKind = 'health';
    } else if (RegExp(r'\b(jio|airtel|vi|recharge|bill|electricity|water|wifi)\b').hasMatch(normalized)) {
      guessedKind = 'bill';
    }
    
    if (guessedKind != null) {
      for (final category in state.categories) {
        if (category.name.toLowerCase().contains(guessedKind) && category.kind == kind) {
          return category;
        }
      }
    }
  }
  for (final category in state.categories) {
    if (category.kind == kind && !category.isArchived) return category;
  }
  return null;
}

String _rowSignature(
  ParsedWalletCsvRow row,
  String accountId,
  String? categoryId,
) {
  final date = row.occurredAt == null ? 'no-date' : _dateKey(row.occurredAt!);
  return [
    accountId,
    row.type,
    row.amount.amountMinor,
    row.amount.currency,
    categoryId ?? '',
    date,
    row.notes?.trim().toLowerCase() ?? '',
  ].join('|');
}

String _transactionSignature(TransactionRecord transaction) {
  return [
    transaction.accountId,
    transaction.type,
    transaction.amount.amountMinor,
    transaction.amount.currency,
    transaction.categoryId ?? '',
    _dateKey(transaction.occurredAt),
    transaction.notes?.trim().toLowerCase() ?? '',
  ].join('|');
}

String _dateKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}

void _ignoreLoadState(LedgerLoadState _) {}
