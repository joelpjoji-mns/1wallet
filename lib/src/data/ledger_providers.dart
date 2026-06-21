import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' as foundation;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../capture/message_parser.dart';
import '../features/capture/sms_spooler.dart';
import '../imports/wallet_csv_parser.dart';
import '../ledger/ledger_selectors.dart';
import '../utils/recurrence_utils.dart';
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

LedgerState fixStaleScheduledTransactions(LedgerState ledger) {
  bool changed = false;
  final now = DateTime.now();
  final List<TransactionRecord> newAutoPosted = [];

  // 1. Generate auto-posted transactions
  for (final scheduled in ledger.transactions) {
    if (scheduled.status == 'scheduled' && scheduled.postMode == 'auto') {
      DateTime nextDate = scheduled.occurredAt;
      while (nextDate.isBefore(now)) {
        final dateStr = '${nextDate.year}${nextDate.month.toString().padLeft(2, '0')}${nextDate.day.toString().padLeft(2, '0')}';
        final autoId = '${scheduled.id}-auto-$dateStr';
        
        final alreadyExists = ledger.transactions.any((t) => t.id == autoId);
        if (!alreadyExists && !newAutoPosted.any((t) => t.id == autoId)) {
          changed = true;
          newAutoPosted.add(
            scheduled.copyWith(
              id: autoId,
              status: 'cleared',
              occurredAt: nextDate,
              originalTransactionId: scheduled.id,
              postMode: null, // Clear postMode on the posted instance
            ),
          );
        }
        nextDate = advanceTransactionRecurrence(nextDate, scheduled);
      }
    }
  }

  // Combine original with new
  final combinedTransactions = [...ledger.transactions, ...newAutoPosted];

  // 2. Build history map
  final Map<String, DateTime> latestHistory = {};
  for (final t in combinedTransactions) {
    if (t.originalTransactionId != null && t.status != 'scheduled' && t.status != 'void') {
      final currentLatest = latestHistory[t.originalTransactionId!];
      if (currentLatest == null || t.occurredAt.isAfter(currentLatest)) {
        latestHistory[t.originalTransactionId!] = t.occurredAt;
      }
    }
  }

  // 3. Advance scheduled cursors based on history map
  final updated = combinedTransactions.map((scheduled) {
    if (scheduled.status != 'scheduled') return scheduled;

    final latestOccurredAt = latestHistory[scheduled.id];
    if (latestOccurredAt == null) return scheduled;

    if (scheduled.occurredAt.isBefore(latestOccurredAt) || scheduled.occurredAt.isAtSameMomentAs(latestOccurredAt)) {
      changed = true;
      DateTime nextDate = scheduled.occurredAt;
      while (nextDate.isBefore(latestOccurredAt) || nextDate.isAtSameMomentAs(latestOccurredAt)) {
         nextDate = advanceTransactionRecurrence(nextDate, scheduled);
      }
      return scheduled.copyWith(occurredAt: nextDate);
    }
    return scheduled;
  }).toList();

  if (!changed) return ledger;
  return ledger.copyWith(transactions: updated);
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
        final fixed = await foundation.compute(fixStaleScheduledTransactions, restored);
        state = fixed;
        unawaited(_repository.save(fixed));
        unawaited(SmsSpooler.updateTriggerWords(fixed));
      } else {
        state = emptyLedgerState();
      }
      _setLoadState(
        LedgerLoadState.ready(hasPersistedLedger: restored != null),
      );
      unawaited(processSpooledSms());
      
      // Start active foreground polling for instant updates
      Timer.periodic(const Duration(seconds: 5), (_) {
        if (!mounted) return;
        unawaited(processSpooledSms());
      });
      
    } catch (error) {
      if (!mounted) return;
      _setLoadState(
        LedgerLoadState.failed('Unable to restore local wallet: $error'),
      );
    }
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
        final timestampStr = payload['timestamp'] as String?;
        final receivedAt = timestampStr != null ? DateTime.tryParse(timestampStr) : null;
        if (body != null && body.isNotEmpty) {
          await importSmsMessage(body, receivedAt: receivedAt);
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
        ? kDefaultCurrency
        : currency.trim().toUpperCase();
    final preferences = LedgerPreferences(
      baseCurrency: normalizedCurrency,
      displayCurrency: normalizedCurrency,
      enabledCurrencies: [normalizedCurrency],
      locale: normalizedCurrency == kDefaultCurrency ? kDefaultLocale : 'en_US',
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

  Timer? _prefsSaveTimer;

  Future<void> updatePreferences(LedgerPreferences preferences) async {
    state = state.copyWith(preferences: preferences);

    // Debounce the heavy disk/cloud save to avoid OutOfMemory / extreme jank during slider drags
    _prefsSaveTimer?.cancel();
    _prefsSaveTimer = Timer(const Duration(milliseconds: 500), () {
      unawaited(_repository.save(state));
    });
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
    String? name,
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
      name: name,
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
    String? name,
    String? notes,
    DateTime? occurredAt,
    String? recurrenceFrequency,
    int? recurrenceInterval,
    List<int>? recurrenceDaysOfWeek,
    List<int>? recurrenceDaysOfMonth,
    bool? isExcludedFromReports,
    String? originalTransactionId,
    String? postMode,
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
      name: _blankToNull(name),
      notes: _blankToNull(notes),
      importBatchId: existing?.importBatchId,
      occurredAt: occurredAt ?? existing?.occurredAt ?? DateTime.now(),
      recurrenceFrequency: recurrenceFrequency ?? existing?.recurrenceFrequency,
      recurrenceInterval: recurrenceInterval ?? existing?.recurrenceInterval ?? 1,
      recurrenceDaysOfWeek:
          recurrenceDaysOfWeek ?? existing?.recurrenceDaysOfWeek,
      recurrenceDaysOfMonth:
          recurrenceDaysOfMonth ?? existing?.recurrenceDaysOfMonth,
      attachments: existing?.attachments ?? const [],
      isReimbursable: existing?.isReimbursable ?? false,
      isTaxDeductible: existing?.isTaxDeductible ?? false,
      isExcludedFromReports:
          isExcludedFromReports ?? existing?.isExcludedFromReports ?? false,
      sourceConfidence: existing?.sourceConfidence,
      externalRef: existing?.externalRef,
      originalTransactionId: originalTransactionId ?? existing?.originalTransactionId,
      postMode: postMode ?? existing?.postMode,
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
      name: existing.name,
      notes: existing.notes,
      occurredAt: occurredAt ?? existing.occurredAt,
      recurrenceFrequency: existing.recurrenceFrequency,
      isExcludedFromReports: existing.isExcludedFromReports,
      originalAmountMinor: existing.originalAmount?.amountMinor,
      originalCurrency: existing.originalAmount?.currency,
      counterAmountMinor: existing.counterAmount?.amountMinor,
      originalTransactionId: existing.originalTransactionId,
    );
  }

  Future<TransactionRecord> postponeTransaction(
    String id,
    DateTime newDate,
  ) async {
    final existing = _transactionById(state, id);
    if (existing == null) throw StateError('Transaction not found.');
    return updateTransactionStatus(
      id,
      existing.status,
      occurredAt: newDate,
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
      name: existing.name,
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
    Map<String, String>? encryptedDetails,
    Money? creditLimit,
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
      encryptedDetails: encryptedDetails ?? existing?.encryptedDetails,
      creditLimit: creditLimit ?? existing?.creditLimit,
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
    Color? color,
  }) async {
    final existing = categoryById(state, id);
    final normalizedParentId = _blankToNull(parentId);
    final parent = categoryById(state, normalizedParentId);
    final normalizedKind = parent?.kind ??
        existing?.kind ??
        (kind.trim().isEmpty ? 'expense' : kind.trim());
    final category = Category(
      id: existing?.id ?? id ?? _newId('cat'),
      name: name.trim().isEmpty ? 'New category' : name.trim(),
      kind: normalizedKind,
      color: color ?? existing?.color,
      parentId: normalizedParentId,
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

  Future<void> deleteCategory(String id) async {
    final isUsedInTx = state.transactions.any((t) => t.categoryId == id);
    final isUsedInRules = state.preferences.futureGenerationRules?.any((r) => r.categoryId == id) ?? false;
    final isUsedInCaptures = state.captureCandidates.any((c) => c.suggestedCategoryId == id);
    final hasChildren = state.categories.any((c) => c.parentId == id);
    final isUsed = isUsedInTx || isUsedInRules || isUsedInCaptures || hasChildren;

    if (isUsed) {
      final categories = [
        for (final category in state.categories)
          category.id == id ? category.copyWith(isArchived: true) : category,
      ];
      await _commit(state.copyWith(categories: categories));
    } else {
      final categories = state.categories.where((category) => category.id != id).toList();
      await _commit(state.copyWith(categories: categories));
    }
  }

  Future<void> updateCaptureCandidateStatus(String id, String status) async {
    final candidates = [
      for (final candidate in state.captureCandidates)
        candidate.id == id ? candidate.copyWith(status: status) : candidate,
    ];
    await _commit(state.copyWith(captureCandidates: candidates));
  }

  Future<void> updateCaptureCandidateStatuses(Iterable<String> ids, String status) async {
    final idSet = ids.toSet();
    final candidates = [
      for (final candidate in state.captureCandidates)
        idSet.contains(candidate.id) ? candidate.copyWith(status: status) : candidate,
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

  Future<List<TransactionRecord>> approveCaptureCandidates(Iterable<String> ids) async {
    final idSet = ids.toSet();
    final newTransactions = <TransactionRecord>[];
    
    final candidates = [
      for (final candidate in state.captureCandidates)
        if (idSet.contains(candidate.id)) () {
          if (candidate.parsedAmount == null) return candidate;
          
          final account = accountById(state, candidate.suggestedAccountId) ??
              state.accounts.where((account) => !account.isArchived).firstOrNull ??
              (state.accounts.isEmpty ? null : state.accounts.first);
          
          if (account == null) return candidate;

          final type = candidate.transactionType == 'income' ? 'income' : 'expense';
          final category = categoryById(state, candidate.suggestedCategoryId) ??
              _matchCategory(state, candidate.merchant, type);
          final amount = candidate.parsedAmount!.copyWith(currency: account.currency);
          
          newTransactions.add(TransactionRecord(
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
          ));
          
          return candidate.copyWith(status: 'approved');
        }() else candidate
    ];

    if (newTransactions.isNotEmpty) {
      await _commit(
        state.copyWith(
          transactions: [...newTransactions, ...state.transactions],
          captureCandidates: candidates,
        ),
      );
    }
    
    return newTransactions;
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
              )
            : candidate,
    ];
    await _commit(state.copyWith(captureCandidates: candidates));
  }

  Future<CaptureCandidate?> importSmsMessage(String rawText, {DateTime? receivedAt}) async {
    final parsed = parseTransactionMessage(
      rawText,
      fallbackCurrency: state.preferences.baseCurrency,
    );
    if (parsed.ignored) return null;
    
    // Check for duplicates
    final isDuplicate = state.captureCandidates.any((c) => c.rawText == parsed.rawText);
    if (isDuplicate) return null;

    String? matchedAccountId = _matchAccountToSms(state, parsed);

    final candidate = CaptureCandidate(
      id: _newId('cap'),
      source: 'sms',
      status: 'pending',
      createdAt: receivedAt ?? DateTime.now(),
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
    );
    await _commit(
      state.copyWith(
        captureCandidates: [candidate, ...state.captureCandidates],
      ),
    );
    return candidate;
  }

  Future<List<CaptureCandidate>> importSmsMessagesBatch(List<({String text, DateTime receivedAt})> messages) async {
    final newCandidates = <CaptureCandidate>[];
    int idx = 0;

    for (final message in messages) {
      final parsed = parseTransactionMessage(
        message.text,
        fallbackCurrency: state.preferences.baseCurrency,
      );
      if (parsed.ignored) continue;

      // Check against existing state and newly added candidates in this batch
      final isDuplicate = state.captureCandidates.any((c) => c.rawText == parsed.rawText) || 
                          newCandidates.any((c) => c.rawText == parsed.rawText);
      if (isDuplicate) continue;

      String? matchedAccountId = _matchAccountToSms(state, parsed);

      final candidate = CaptureCandidate(
        id: '${_newId('cap')}-${idx++}',
        source: 'sms',
        status: 'pending',
        createdAt: message.receivedAt,
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
      );
      newCandidates.add(candidate);
    }

    if (newCandidates.isNotEmpty) {
      await _commit(
        state.copyWith(
          captureCandidates: [...newCandidates, ...state.captureCandidates],
        ),
      );
    }

    return newCandidates;
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
    DateTime? targetDate,
    String frequency = 'monthly',
    int interval = 1,
    List<int>? daysOfWeek,
    List<int>? daysOfMonth,
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
      targetDate: targetDate,
      frequency: frequency,
      interval: interval,
      daysOfWeek: daysOfWeek,
      daysOfMonth: daysOfMonth,
    );
    await _commit(state.copyWith(budgets: [budget, ...state.budgets]));
  }

  Future<void> addGoal({
    required String name,
    required int targetMinor,
    String? currency,
    DateTime? targetDate,
    String frequency = 'once',
    int interval = 1,
    List<int>? daysOfWeek,
    List<int>? daysOfMonth,
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
      targetDate: targetDate,
      frequency: frequency,
      interval: interval,
      daysOfWeek: daysOfWeek,
      daysOfMonth: daysOfMonth,
    );
    await _commit(state.copyWith(goals: [goal, ...state.goals]));
  }

  Future<void> postponeBudget(String id, DateTime newDate) async {
    final budgets = [
      for (final b in state.budgets)
        b.id == id ? b.copyWith(targetDate: newDate) : b,
    ];
    await _commit(state.copyWith(budgets: budgets));
  }

  Future<void> postponeGoal(String id, DateTime newDate) async {
    final goals = [
      for (final g in state.goals)
        g.id == id ? g.copyWith(targetDate: newDate) : g,
    ];
    await _commit(state.copyWith(goals: goals));
  }

  Future<void> addEnabledCurrency(String currency) async {
    final normalized = currency.trim().toUpperCase();
    if (normalized.isEmpty) return;
    if (state.preferences.enabledCurrencies.contains(normalized)) return;
    final enabled = <String>{
      ...state.preferences.enabledCurrencies,
      normalized,
    }.toList()..sort();
    await _commit(
      state.copyWith(
        preferences: state.preferences.copyWith(
          enabledCurrencies: enabled,
        ),
      ),
    );
  }

  Future<void> removeEnabledCurrency(String currency) async {
    final normalized = currency.trim().toUpperCase();
    if (normalized == state.preferences.baseCurrency.toUpperCase()) return;
    final enabled = state.preferences.enabledCurrencies
        .where((c) => c.toUpperCase() != normalized)
        .toList();
    final newRates = state.exchangeRates.where((r) => 
      r.base.toUpperCase() != normalized && r.quote.toUpperCase() != normalized
    ).toList();
    await _commit(
      state.copyWith(
        preferences: state.preferences.copyWith(
          enabledCurrencies: enabled,
        ),
        exchangeRates: newRates,
      ),
    );
  }

  Future<void> setExchangeRate({
    required String base,
    required String quote,
    required double rate,
  }) async {
    final normalizedBase = base.trim().toUpperCase();
    final normalizedQuote = quote.trim().toUpperCase();
    if (normalizedBase == normalizedQuote) return;

    final existingIndex = state.exchangeRates.indexWhere(
      (r) => r.base.toUpperCase() == normalizedBase && r.quote.toUpperCase() == normalizedQuote,
    );

    final record = ExchangeRateRecord(
      base: normalizedBase,
      quote: normalizedQuote,
      rate: rate,
      asOfDate: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final rates = [...state.exchangeRates];
    if (existingIndex >= 0) {
      rates[existingIndex] = record;
    } else {
      rates.add(record);
    }
    await _commit(state.copyWith(exchangeRates: rates));
  }

  Future<void> setExchangeRatesDirectly(List<ExchangeRateRecord> rates) async {
    await _commit(state.copyWith(exchangeRates: rates));
  }

  Timer? _autoBackupTimer;

  Future<void> _commit(LedgerState next) async {
    final normalized = normalizeLedgerState(next);
    state = normalized;
    await _repository.save(normalized);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_unsynced_changes', true);
    
    unawaited(SmsSpooler.updateTriggerWords(normalized));
    
    _autoBackupTimer?.cancel();
    _autoBackupTimer = Timer(const Duration(seconds: 3), () {
      unawaited(_performAutoBackup(normalized));
    });
  }

  Future<void> _performAutoBackup(LedgerState ledger) async {
    if (foundation.kIsWeb) return;
    try {
      final archive = await foundation.compute(_encodeForBackup, ledger);
      
      // 1. App documents directory -> 1Wallet subfolder
      final docsDir = await getApplicationDocumentsDirectory();
      final docsSubDir = Directory('${docsDir.path}/1Wallet');
      await docsSubDir.create(recursive: true);
      final docsFile = File('${docsSubDir.path}/1wallet_auto_backup.onewallet');
      await docsFile.writeAsString(archive);
      
      // 2. App external storage directory -> 1Wallet subfolder (Android only)
      if (!foundation.kIsWeb && Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final extSubDir = Directory('${extDir.path}/1Wallet');
          await extSubDir.create(recursive: true);
          final extFile = File('${extSubDir.path}/1wallet_auto_backup.onewallet');
          await extFile.writeAsString(archive);
        }
        
        // 3. Public Download directory -> 1Wallet subfolder (best-effort)
        try {
          final downloadDir = Directory('/storage/emulated/0/Download');
          if (await downloadDir.exists()) {
            final downloadSubDir = Directory('${downloadDir.path}/1Wallet');
            await downloadSubDir.create(recursive: true);
            final downloadFile = File('${downloadSubDir.path}/1wallet_auto_backup.onewallet');
            await downloadFile.writeAsString(archive);
          }
        } catch (_) {}

        // 4. Public Documents directory -> 1Wallet subfolder (best-effort)
        try {
          final documentsDir = Directory('/storage/emulated/0/Documents');
          if (await documentsDir.exists()) {
            final documentsSubDir = Directory('${documentsDir.path}/1Wallet');
            await documentsSubDir.create(recursive: true);
            final documentsFile = File('${documentsSubDir.path}/1wallet_auto_backup.onewallet');
            await documentsFile.writeAsString(archive);
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Auto backup failed: $e');
    }
  }

  Future<File?> getLatestAutoBackupFile() async {
    if (foundation.kIsWeb) return null;
    final candidates = <File>[];
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      candidates.add(File('${docsDir.path}/1Wallet/1wallet_auto_backup.onewallet'));
      candidates.add(File('${docsDir.path}/1wallet_auto_backup.onewallet'));
      
      if (Platform.isAndroid) {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          candidates.add(File('${extDir.path}/1Wallet/1wallet_auto_backup.onewallet'));
          candidates.add(File('${extDir.path}/1wallet_auto_backup.onewallet'));
        }
        candidates.add(File('/storage/emulated/0/Download/1Wallet/1wallet_auto_backup.onewallet'));
        candidates.add(File('/storage/emulated/0/Download/1wallet_auto_backup.onewallet'));
        candidates.add(File('/storage/emulated/0/Documents/1Wallet/1wallet_auto_backup.onewallet'));
        candidates.add(File('/storage/emulated/0/Documents/1wallet_auto_backup.onewallet'));
      }
    } catch (_) {}

    File? newest;
    DateTime? newestTime;
    for (final file in candidates) {
      try {
        if (await file.exists()) {
          final stat = await file.stat();
          if (newestTime == null || stat.modified.isAfter(newestTime)) {
            newestTime = stat.modified;
            newest = file;
          }
        }
      } catch (_) {}
    }
    return newest;
  }

  Future<void> restoreFromAutoBackup(File file) async {
    final content = await file.readAsString();
    await importArchive(content);
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
  final active = state.categories
      .where((category) => !category.isArchived)
      .toList();
  final normalized = name?.trim().toLowerCase();
  
  if (normalized != null && normalized.isNotEmpty) {
    // 1. Check previous transactions for exact or partial name match
    // to find the most recently used category for this merchant.
    for (final tx in state.transactions) {
      final txNotes = tx.notes?.trim().toLowerCase();
      final txName = tx.name?.trim().toLowerCase();
      
      bool isStrongMatch(String? pastString) {
        if (pastString == null) return false;
        if (pastString == normalized) return true;
        if (pastString.length > 4 && normalized.contains(pastString)) return true;
        if (normalized.length > 4 && pastString.contains(normalized)) return true;
        return false;
      }

      if (isStrongMatch(txNotes) || isStrongMatch(txName)) {
        if (tx.categoryId != null) {
          final cat = categoryById(state, tx.categoryId);
          if (cat != null && !cat.isArchived) {
            return cat;
          }
        }
      }
    }

    // 2. Exact match against category names
    for (final category in active) {
      if (category.name.toLowerCase() == normalized) return category;
    }

    // 3. Keyword matching
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
      for (final category in active) {
        if (category.name.toLowerCase().contains(guessedKind)) {
          return category;
        }
      }
    }
  }
  
  return null;
}

String? _matchAccountToSms(LedgerState state, ParsedTransactionMessage parsed) {
  final activeAccounts = state.accounts.where((a) => !a.isArchived).toList();
  if (activeAccounts.isEmpty) return null;

  final rawTextLower = parsed.rawText.toLowerCase();
  
  Account? bestMatch;
  int highestScore = -1;

  for (final account in activeAccounts) {
    int score = 0;

    // 1. Exact Account Number Match (Overkill)
    // Try to match exact account number from encrypted details if we have access to it in memory
    // or from accountLast4 / cardLast4
    if (parsed.last4 != null) {
      if (account.accountLast4 == parsed.last4 || account.cardLast4 == parsed.last4) {
        score += 100; // Strongest indicator
      }
      
      // If the parsed "last4" is actually longer (like a full account number)
      // we check if it matches the encrypted details 'accountNumber'
      if (parsed.last4!.length > 4 && account.encryptedDetails != null) {
        final accNum = account.encryptedDetails!['accountNumber'];
        if (accNum != null && accNum.replaceAll(RegExp(r'\D'), '').endsWith(parsed.last4!)) {
          score += 150;
        }
      }
    }

    // 2. Institution Match
    if (parsed.institutionName != null && account.institution != null) {
      if (account.institution!.toLowerCase().contains(parsed.institutionName!.toLowerCase())) {
        score += 50;
      }
    } else if (account.institution != null) {
      // Look for the institution directly in the raw SMS
      if (rawTextLower.contains(account.institution!.toLowerCase())) {
        score += 30;
      }
    }

    // 3. Name or Group Name Match
    if (rawTextLower.contains(account.name.toLowerCase())) {
      score += 40;
    }
    if (account.groupName != null && rawTextLower.contains(account.groupName!.toLowerCase())) {
      score += 20;
    }

    // 4. Currency tie-breaker
    if (parsed.amount != null && parsed.amount!.currency == account.currency) {
      score += 5;
    }

    if (score > highestScore && score > 0) {
      highestScore = score;
      bestMatch = account;
    }
  }

  return bestMatch?.id;
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

String _encodeForBackup(LedgerState state) {
  return encodeLedgerArchive(state, source: 'flutter-local');
}
