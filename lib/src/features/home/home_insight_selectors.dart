import '../../data/ledger_models.dart';
import '../../ledger/ledger_selectors.dart';
import '../../utils/recurrence_utils.dart';

/// Pinned salary plan id for the Payday widget, stored alongside the other
/// per-widget settings in `LedgerPreferences.homeWidgetFilters`.
const paydayPinnedPlanKey = 'paydayCountdown';

/// A missed salary keeps showing as late for this many days before the widget
/// rolls forward to the next occurrence.
const paydayLateGraceDays = 7;

const _billTypes = {
  'expense',
  'fee',
  'interest_out',
  'card_payment',
  'loan_repayment',
};

const _spendTypes = {'expense', 'fee', 'interest_out'};

const _inactiveStatuses = {'scheduled', 'paused', 'void', 'finished'};

DateTime _dateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

/// Calendar-day difference that ignores daylight-saving hour shifts.
int calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

bool _accountUsable(Account? account) =>
    account == null || (!account.isDeleted && !account.isArchived);

List<TransactionRecord> _postedChildren(
  LedgerState state,
  TransactionRecord plan,
) {
  return [
    for (final t in state.transactions)
      if (t.originalTransactionId == plan.id &&
          !_inactiveStatuses.contains(t.status))
        t,
  ];
}

/// Whether a scheduled plan can still produce an occurrence on [date].
bool _planRunsOn(TransactionRecord plan, DateTime date, int postedCount) {
  final end = plan.recurrenceEndDate;
  if (end != null && _dateOnly(date).isAfter(_dateOnly(end))) return false;
  final limit = plan.recurrenceLimit;
  if (limit != null && limit > 0 && postedCount >= limit) return false;
  return true;
}

bool _isRecurring(TransactionRecord plan) {
  final freq = plan.recurrenceFrequency;
  return freq != null && freq != 'once';
}

/// An active income plan that represents a salary: income in the Salary
/// category tree, or an income plan named like a salary.
bool isSalaryPlan(LedgerState state, TransactionRecord plan) {
  if (plan.status != 'scheduled' || plan.type != 'income') return false;
  final category = categoryById(state, plan.categoryId);
  if (category != null) {
    final root = rootCategoryFor(state, category);
    if (root.id == 'cat-salary' || category.id == 'cat-salary') return true;
    final names = '${category.name} ${root.name}'.toLowerCase();
    if (names.contains('salary') || names.contains('payroll')) return true;
  }
  final name = (plan.name ?? '').toLowerCase();
  return name.contains('salary') ||
      name.contains('payroll') ||
      name.contains('paycheck') ||
      name.contains('pay cheque');
}

class PaydayBill {
  const PaydayBill({
    required this.name,
    required this.dueDate,
    required this.amount,
    this.planId,
    this.cardAccountId,
  });

  final String name;
  final DateTime dueDate;

  /// Converted to the display currency.
  final Money amount;
  final String? planId;
  final String? cardAccountId;
}

class PaydayInfo {
  const PaydayInfo({
    required this.plan,
    required this.payday,
    required this.daysUntil,
    required this.missedCount,
    required this.cycleStart,
    required this.account,
    required this.bills,
    required this.billsTotal,
    required this.leftAfterBills,
    required this.otherPlanIds,
  });

  final TransactionRecord plan;

  /// Next expected salary date (date only). In the past when late.
  final DateTime payday;

  /// Calendar days until [payday]; negative when the salary is late.
  final int daysUntil;

  /// Occurrences skipped over after the late grace period expired.
  final int missedCount;

  /// Start of the current pay cycle (last posted salary), if known.
  final DateTime? cycleStart;
  final Account? account;
  final List<PaydayBill> bills;
  final Money billsTotal;

  /// Salary account balance minus [billsTotal]; null without an account.
  final Money? leftAfterBills;

  /// Other active salary plans, nearest first.
  final List<String> otherPlanIds;

  bool get isToday => daysUntil == 0;
  bool get isLate => daysUntil < 0;

  /// Pay-cycle completion between 0 and 1, or null when unknown.
  double? get cycleProgress {
    final start = cycleStart;
    if (start == null) return null;
    final total = calendarDaysBetween(start, payday);
    if (total <= 0) return null;
    final elapsed = total - daysUntil;
    return (elapsed / total).clamp(0.0, 1.0);
  }

  int? get cycleLength {
    final start = cycleStart;
    if (start == null) return null;
    final total = calendarDaysBetween(start, payday);
    return total > 0 ? total : null;
  }
}

({DateTime payday, int missed})? _resolvePayday(
  LedgerState state,
  TransactionRecord plan,
  DateTime today,
) {
  final postedCount = _postedChildren(state, plan).length;
  var payday = _dateOnly(plan.occurredAt);
  if (!_planRunsOn(plan, payday, postedCount)) return null;
  var missed = 0;
  final lateDays = calendarDaysBetween(payday, today);
  if (lateDays > paydayLateGraceDays && _isRecurring(plan)) {
    var cursor = plan.occurredAt;
    for (var i = 0; i < 500 && _dateOnly(cursor).isBefore(today); i++) {
      final next = advanceTransactionRecurrence(cursor, plan);
      if (!next.isAfter(cursor)) break;
      cursor = next;
      missed++;
    }
    payday = _dateOnly(cursor);
    if (!_planRunsOn(plan, payday, postedCount + missed)) return null;
  }
  return (payday: payday, missed: missed);
}

/// Next salary for the Payday widget, or null when no active salary plan
/// exists. Paused, finished, ended and deleted-account plans are ignored.
PaydayInfo? paydayInfo(LedgerState state, {DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  final candidates =
      <({TransactionRecord plan, DateTime payday, int missed})>[];
  for (final plan in scheduledTransactions(state)) {
    if (!isSalaryPlan(state, plan)) continue;
    final account = accountById(state, plan.accountId);
    if (!_accountUsable(account)) continue;
    final resolved = _resolvePayday(state, plan, today);
    if (resolved == null) continue;
    candidates.add((
      plan: plan,
      payday: resolved.payday,
      missed: resolved.missed,
    ));
  }
  if (candidates.isEmpty) return null;
  candidates.sort((a, b) {
    final byDate = a.payday.compareTo(b.payday);
    if (byDate != 0) return byDate;
    return b.plan.amount.amountMinor.compareTo(a.plan.amount.amountMinor);
  });

  final pinnedId = state.preferences.homeWidgetFilters[paydayPinnedPlanKey];
  final chosen = candidates.firstWhere(
    (c) => c.plan.id == pinnedId,
    orElse: () => candidates.first,
  );
  final plan = chosen.plan;
  final payday = chosen.payday;
  final account = accountById(state, plan.accountId);

  DateTime? cycleStart;
  for (final child in _postedChildren(state, plan)) {
    final date = _dateOnly(child.occurredAt);
    if (!date.isBefore(payday)) continue;
    if (cycleStart == null || date.isAfter(cycleStart)) cycleStart = date;
  }

  final displayCurrency = state.preferences.displayCurrency.toUpperCase();
  final bills = paydayBillsBefore(state, payday, today: today);
  final billsTotalMinor = bills.fold<int>(
    0,
    (sum, bill) => sum + bill.amount.amountMinor,
  );
  final billsTotal = Money(
    amountMinor: billsTotalMinor,
    currency: displayCurrency,
  );
  Money? left;
  if (account != null) {
    final balance = convertMoneyForDisplay(
      state,
      accountBalance(state, account),
      displayCurrency,
    );
    left = Money(
      amountMinor: balance.amountMinor - billsTotalMinor,
      currency: displayCurrency,
    );
  }

  return PaydayInfo(
    plan: plan,
    payday: payday,
    daysUntil: calendarDaysBetween(today, payday),
    missedCount: chosen.missed,
    cycleStart: cycleStart,
    account: account,
    bills: bills,
    billsTotal: billsTotal,
    leftAfterBills: left,
    otherPlanIds: [
      for (final c in candidates)
        if (c.plan.id != plan.id) c.plan.id,
    ],
  );
}

/// Bills owed before [payday]: unpaid scheduled expense/EMI/card plans
/// (including overdue occurrences) and unpaid card bills not already covered
/// by a scheduled card payment. Transfers between own accounts are excluded.
List<PaydayBill> paydayBillsBefore(
  LedgerState state,
  DateTime payday, {
  DateTime? today,
}) {
  final displayCurrency = state.preferences.displayCurrency.toUpperCase();
  final day = _dateOnly(today ?? DateTime.now());
  final bills = <PaydayBill>[];
  final coveredCards = <String>{};
  for (final plan in scheduledTransactions(state)) {
    if (plan.status != 'scheduled' || !_billTypes.contains(plan.type)) {
      continue;
    }
    if (!_accountUsable(accountById(state, plan.accountId))) continue;
    var posted = _postedChildren(state, plan).length;
    var cursor = plan.occurredAt;
    for (var i = 0; i < 60; i++) {
      final due = _dateOnly(cursor);
      if (!due.isBefore(payday)) break;
      if (!_planRunsOn(plan, due, posted)) break;
      bills.add(
        PaydayBill(
          name: planDisplayName(state, plan),
          dueDate: due,
          amount: convertMoneyForDisplay(
            state,
            plan.amount.copyWith(amountMinor: plan.amount.amountMinor.abs()),
            displayCurrency,
          ),
          planId: plan.id,
        ),
      );
      if (plan.type == 'card_payment' && plan.counterAccountId != null) {
        coveredCards.add(plan.counterAccountId!);
      }
      posted++;
      if (!_isRecurring(plan)) break;
      final next = advanceTransactionRecurrence(cursor, plan);
      if (!next.isAfter(cursor)) break;
      cursor = next;
    }
  }
  for (final card in cardBills(state, now: day)) {
    if (coveredCards.contains(card.status.account.id)) continue;
    if (card.status.isPaid || card.owed.amountMinor <= 0) continue;
    if (!_dateOnly(card.status.dueDate).isBefore(payday)) continue;
    bills.add(
      PaydayBill(
        name: card.status.account.name,
        dueDate: _dateOnly(card.status.dueDate),
        amount: convertMoneyForDisplay(state, card.owed, displayCurrency),
        cardAccountId: card.status.account.id,
      ),
    );
  }
  bills.sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return bills;
}

class CardBillInfo {
  const CardBillInfo({required this.status, required this.owed});

  final CreditCardDueStatus status;

  /// Outstanding card balance in the card currency (never negative).
  final Money owed;

  bool get hasNothingDue => owed.amountMinor <= 0;
}

/// Active credit cards with a statement or due day, most urgent first:
/// unpaid bills ordered by due date (overdue first), then paid cards.
List<CardBillInfo> cardBills(LedgerState state, {DateTime? now}) {
  final items = <CardBillInfo>[];
  for (final account in state.accounts) {
    if (account.isDeleted || account.isArchived) continue;
    final status = creditCardDueStatus(state, account, now: now);
    if (status == null) continue;
    final balance = accountBalance(state, account);
    final owedMinor = balance.amountMinor < 0 ? -balance.amountMinor : 0;
    items.add(
      CardBillInfo(
        status: status,
        owed: Money(amountMinor: owedMinor, currency: account.currency),
      ),
    );
  }
  int rank(CardBillInfo item) =>
      item.status.isPaid || item.hasNothingDue ? 1 : 0;
  items.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    return a.status.dueDate.compareTo(b.status.dueDate);
  });
  return items;
}

class CategorySpike {
  const CategorySpike({
    required this.category,
    required this.current,
    required this.baseline,
  });

  final Category category;
  final Money current;
  final Money baseline;

  bool get isNew => baseline.amountMinor <= 0;

  /// Relative change versus the baseline, e.g. 0.64 for +64%.
  double get change => isNew
      ? double.infinity
      : (current.amountMinor - baseline.amountMinor) / baseline.amountMinor;
}

class CategorySpikeResult {
  const CategorySpikeResult({
    required this.items,
    required this.monthsCompared,
    required this.dayOfMonth,
  });

  final List<CategorySpike> items;

  /// Previous months with spending used for the average (0 to 3).
  final int monthsCompared;
  final int dayOfMonth;

  bool get hasEnoughHistory => monthsCompared >= 2;
}

/// Spending per root category from the 1st of each month up to the same day
/// of the month, so early-month totals are compared like for like.
CategorySpikeResult categorySpikes(
  LedgerState state, {
  DateTime? now,
  int limit = 3,
  double minChange = 0.2,
}) {
  final today = _dateOnly(now ?? DateTime.now());
  final displayCurrency = state.preferences.displayCurrency.toUpperCase();

  Map<String, int> spendFor(DateTime monthStart) {
    final lastDay = DateTime(monthStart.year, monthStart.month + 1, 0).day;
    final end = DateTime(
      monthStart.year,
      monthStart.month,
      today.day.clamp(1, lastDay) + 1,
    );
    final totals = <String, int>{};
    for (final t in state.transactions) {
      if (_inactiveStatuses.contains(t.status)) continue;
      final isSpend = _spendTypes.contains(t.type);
      final isRefund = t.type == 'refund';
      if (!isSpend && !isRefund) continue;
      if (t.occurredAt.isBefore(monthStart) || !t.occurredAt.isBefore(end)) {
        continue;
      }
      final category = categoryById(state, t.categoryId);
      if (category == null) continue;
      final root = rootCategoryFor(state, category);
      final amount = convertMoneyForDisplay(
        state,
        t.amount.copyWith(amountMinor: t.amount.amountMinor.abs()),
        displayCurrency,
      ).amountMinor;
      totals[root.id] = (totals[root.id] ?? 0) + (isSpend ? amount : -amount);
    }
    totals.updateAll((_, value) => value < 0 ? 0 : value);
    return totals;
  }

  final current = spendFor(DateTime(today.year, today.month));
  final previous = <Map<String, int>>[];
  for (var back = 1; back <= 3; back++) {
    final totals = spendFor(DateTime(today.year, today.month - back));
    if (totals.values.any((value) => value > 0)) previous.add(totals);
  }
  if (previous.length < 2) {
    return CategorySpikeResult(
      items: const [],
      monthsCompared: previous.length,
      dayOfMonth: today.day,
    );
  }

  final baseline = <String, int>{};
  for (final month in previous) {
    month.forEach((id, value) => baseline[id] = (baseline[id] ?? 0) + value);
  }
  baseline.updateAll((_, value) => (value / previous.length).round());

  int sum(Map<String, int> values) =>
      values.values.fold(0, (total, value) => total + value);
  final reference = [
    sum(current),
    sum(baseline),
  ].reduce((a, b) => a > b ? a : b);
  final minorFactor = _pow10(minorUnits(displayCurrency));
  final floor = [
    reference * 0.05,
    10.0 * minorFactor,
  ].reduce((a, b) => a > b ? a : b);

  final spikes = <CategorySpike>[];
  for (final id in {...current.keys, ...baseline.keys}) {
    final now = current[id] ?? 0;
    final base = baseline[id] ?? 0;
    if ((now > base ? now : base) < floor) continue;
    final category = categoryById(state, id);
    if (category == null) continue;
    final spike = CategorySpike(
      category: category,
      current: Money(amountMinor: now, currency: displayCurrency),
      baseline: Money(amountMinor: base, currency: displayCurrency),
    );
    if (spike.isNew ? now <= 0 : spike.change.abs() < minChange) continue;
    spikes.add(spike);
  }
  spikes.sort((a, b) {
    final byIncrease = (b.change > 0 ? 1 : 0).compareTo(a.change > 0 ? 1 : 0);
    if (byIncrease != 0) return byIncrease;
    return b.change.abs().compareTo(a.change.abs());
  });
  return CategorySpikeResult(
    items: spikes.take(limit).toList(),
    monthsCompared: previous.length,
    dayOfMonth: today.day,
  );
}

double _pow10(int exponent) {
  var value = 1.0;
  for (var i = 0; i < exponent; i++) {
    value *= 10;
  }
  return value;
}
