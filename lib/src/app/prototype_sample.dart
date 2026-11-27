import '../data/ledger_defaults.dart';
import '../data/ledger_models.dart';
import '../design/tokens.dart';

LedgerState prototypeSample(DateTime now) {
  final today = DateTime(now.year, now.month, now.day, 10, 30);
  const inrPerUnit = {
    'INR': 1,
    'USD': 84,
    'EUR': 92,
    'GBP': 106,
    'AED': 23,
    'CAD': 62,
  };
  Money money(int minor, [String currency = 'INR']) =>
      Money(amountMinor: minor, currency: currency);
  DateTime monthDate(int offset, int day) {
    final month = DateTime(today.year, today.month + offset);
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    return DateTime(month.year, month.month, day.clamp(1, lastDay), 10, 30);
  }

  final cycle = '${today.year}-${today.month.toString().padLeft(2, '0')}';
  final accounts = [
    Account(
      id: 'demo-bank',
      name: 'Everyday Bank',
      type: 'bank',
      currency: 'INR',
      openingBalance: money(8500000),
      color: AppColors.primary,
      groupName: 'Everyday',
      accountLast4: '1042',
    ),
    Account(
      id: 'demo-cash',
      name: 'Cash Wallet',
      type: 'cash',
      currency: 'INR',
      openingBalance: money(250000),
      color: AppColors.tertiary,
      groupName: 'Everyday',
    ),
    Account(
      id: 'demo-wallet',
      name: 'UPI & Travel Wallet',
      type: 'wallet',
      currency: 'INR',
      openingBalance: money(1500000),
      color: AppColors.primary,
      groupName: 'Everyday',
    ),
    Account(
      id: 'demo-savings',
      name: 'Emergency Savings',
      type: 'savings',
      currency: 'INR',
      openingBalance: money(35000000),
      color: AppColors.tertiary,
      groupName: 'Savings',
    ),
    Account(
      id: 'demo-investment',
      name: 'Index Fund Portfolio',
      type: 'investment',
      currency: 'INR',
      openingBalance: money(60000000),
      color: AppColors.primary,
      groupName: 'Investments',
    ),
    Account(
      id: 'demo-usd',
      name: 'Freelance USD',
      type: 'bank',
      currency: 'USD',
      openingBalance: money(450000, 'USD'),
      color: AppColors.primary,
      groupName: 'International',
      accountLast4: '2078',
    ),
    Account(
      id: 'demo-eur',
      name: 'Europe Savings',
      type: 'savings',
      currency: 'EUR',
      openingBalance: money(230000, 'EUR'),
      color: AppColors.tertiary,
      groupName: 'International',
    ),
    Account(
      id: 'demo-gbp',
      name: 'London Travel Wallet',
      type: 'wallet',
      currency: 'GBP',
      openingBalance: money(150000, 'GBP'),
      color: AppColors.warning,
      groupName: 'International',
    ),
    Account(
      id: 'demo-aed',
      name: 'Dubai Account',
      type: 'bank',
      currency: 'AED',
      openingBalance: money(850000, 'AED'),
      color: AppColors.primary,
      groupName: 'International',
    ),
    Account(
      id: 'demo-cad',
      name: 'Canada Investments',
      type: 'investment',
      currency: 'CAD',
      openingBalance: money(175000, 'CAD'),
      color: AppColors.tertiary,
      groupName: 'Investments',
    ),
    Account(
      id: 'demo-card',
      name: 'Everyday Credit Card',
      type: 'credit_card',
      currency: 'INR',
      openingBalance: money(-1850000),
      color: AppColors.warning,
      groupName: 'Cards',
      cardLast4: '4412',
      creditLimit: money(20000000),
      statementDay: today.day <= 21 ? today.day + 1 : 1,
      notifyDaysBeforeDue: 3,
    ),
    Account(
      id: 'demo-card-soon',
      name: 'Rewards Card - Due Today',
      type: 'credit_card',
      currency: 'INR',
      openingBalance: money(-3200000),
      color: AppColors.primary,
      groupName: 'Cards',
      cardLast4: '8876',
      creditLimit: money(30000000),
      dueDay: today.day,
      notifyDaysBeforeDue: 7,
    ),
    Account(
      id: 'demo-card-statement',
      name: 'Travel Card - Statement Ready',
      type: 'credit_card',
      currency: 'USD',
      openingBalance: money(-86000, 'USD'),
      color: AppColors.tertiary,
      groupName: 'Cards',
      cardLast4: '3201',
      creditLimit: money(500000, 'USD'),
      statementDay: today.day,
      notifyDaysBeforeDue: 3,
      lastPaidBillMonth:
          '${monthDate(-1, 1).year}-${monthDate(-1, 1).month.toString().padLeft(2, '0')}',
    ),
    Account(
      id: 'demo-card-paid',
      name: 'Sterling Card - Paid',
      type: 'credit_card',
      currency: 'GBP',
      openingBalance: money(-45000, 'GBP'),
      color: AppColors.primary,
      groupName: 'Cards',
      creditLimit: money(200000, 'GBP'),
      dueDay: today.day,
      lastPaidBillMonth: cycle,
    ),
    Account(
      id: 'demo-loan',
      name: 'Home Loan',
      type: 'loan',
      currency: 'INR',
      openingBalance: money(-240000000),
      color: AppColors.dangerLight,
      groupName: 'Loans',
      includeInTotals: false,
      showOnHome: false,
      loanDetails: AccountLoanDetails(
        loanKind: 'loan',
        principal: money(240000000),
        repaymentAmount: money(4200000),
        interestRatePercent: 8.4,
        repaymentCount: 72,
        repaymentStartsOn: monthDate(-24, 6),
        repaymentSourceAccountId: 'demo-bank',
      ),
    ),
    Account(
      id: 'demo-car-loan',
      name: 'Car Loan',
      type: 'loan',
      currency: 'INR',
      openingBalance: money(-60000000),
      color: AppColors.warning,
      groupName: 'Loans',
      includeInTotals: false,
      showOnHome: false,
      loanDetails: AccountLoanDetails(
        loanKind: 'loan',
        principal: money(60000000),
        repaymentAmount: money(1250000),
        interestRatePercent: 7.5,
        repaymentCount: 60,
        repaymentStartsOn: monthDate(-18, 9),
        repaymentSourceAccountId: 'demo-bank',
      ),
    ),
    Account(
      id: 'demo-education-loan',
      name: 'Education Loan USD',
      type: 'loan',
      currency: 'USD',
      openingBalance: money(-1800000, 'USD'),
      color: AppColors.primary,
      groupName: 'Loans',
      includeInTotals: false,
      showOnHome: false,
      loanDetails: AccountLoanDetails(
        loanKind: 'loan',
        principal: money(1800000, 'USD'),
        repaymentAmount: money(26000, 'USD'),
        interestRatePercent: 4.9,
        repaymentCount: 84,
        repaymentStartsOn: monthDate(-12, 12),
        repaymentSourceAccountId: 'demo-usd',
      ),
    ),
    Account(
      id: 'demo-paid-loan',
      name: 'Laptop Loan - Paid Off',
      type: 'loan',
      currency: 'INR',
      openingBalance: money(-9600000),
      color: AppColors.tertiary,
      groupName: 'Closed',
      includeInTotals: false,
      showOnHome: false,
      loanDetails: AccountLoanDetails(
        loanKind: 'loan',
        principal: money(9600000),
        repaymentAmount: money(800000),
        repaymentCount: 12,
        repaymentStartsOn: monthDate(-18, 15),
        repaymentSourceAccountId: 'demo-bank',
      ),
    ),
    Account(
      id: 'demo-overdraft',
      name: 'Business Overdraft',
      type: 'overdraft',
      currency: 'INR',
      openingBalance: money(-5000000),
      color: AppColors.dangerLight,
      groupName: 'Loans',
      includeInTotals: false,
      showOnHome: false,
      loanDetails: AccountLoanDetails(
        loanKind: 'overdraft',
        principal: money(5000000),
        repaymentAmount: money(250000),
        repaymentSourceAccountId: 'demo-bank',
      ),
    ),
    Account(
      id: 'demo-archived',
      name: 'Old Euro Cash - Archived',
      type: 'cash',
      currency: 'EUR',
      openingBalance: money(12000, 'EUR'),
      color: AppColors.tertiary,
      groupName: 'Closed',
      isArchived: true,
      showOnHome: false,
    ),
  ];
  final byId = {for (final account in accounts) account.id: account};
  final transactions = <TransactionRecord>[];

  TransactionRecord record(
    String id,
    String type,
    int minor,
    DateTime date,
    String notes, {
    String account = 'demo-bank',
    String? counterAccount,
    String category = 'cat-grocery',
    String status = 'cleared',
    String source = 'manual',
    String? parent,
    String? importBatch,
    List<String> tags = const [],
  }) {
    final currency = byId[account]!.currency;
    final counterCurrency = counterAccount == null
        ? null
        : byId[counterAccount]!.currency;
    return TransactionRecord(
      id: id,
      type: type,
      status: status,
      source: source,
      accountId: account,
      counterAccountId: counterAccount,
      amount: money(minor, currency),
      baseAmount: money(minor * inrPerUnit[currency]!),
      counterAmount: counterCurrency == null
          ? null
          : money(
              (minor * inrPerUnit[currency]! +
                      inrPerUnit[counterCurrency]! ~/ 2) ~/
                  inrPerUnit[counterCurrency]!,
              counterCurrency,
            ),
      fxRate: inrPerUnit[currency]!.toDouble(),
      categoryId: category,
      occurredAt: date,
      name: notes,
      notes: notes,
      originalTransactionId: parent,
      importBatchId: importBatch,
      tags: tags,
      paymentMethod: account == 'demo-cash' ? 'Cash' : 'Bank transfer',
    );
  }

  void plan(
    String id,
    String name,
    int minor, {
    String type = 'expense',
    String account = 'demo-bank',
    String? counterAccount,
    String category = 'cat-bills',
    int dueInDays = 4,
    String frequency = 'monthly',
    int interval = 1,
    int paid = 12,
    int? limit,
    String status = 'scheduled',
    DateTime? due,
    DateTime? endsOn,
    bool automatic = false,
  }) {
    final next = due ?? today.add(Duration(days: dueInDays));
    final template = record(
      id,
      type,
      minor,
      next,
      name,
      account: account,
      counterAccount: counterAccount,
      category: category,
      status: status,
      source: 'recurring',
    );
    transactions.add(
      template.copyWith(
        recurrenceFrequency: frequency,
        recurrenceInterval: interval,
        recurrenceLimit: limit,
        recurrenceEndDate: endsOn,
        postMode: automatic ? 'auto' : null,
        recurrenceDaysOfMonth: frequency == 'monthly' ? [next.day] : null,
      ),
    );
    for (var i = 1; i <= paid; i++) {
      final DateTime date;
      if (frequency == 'weekly' || frequency == 'daily') {
        date = next.subtract(
          Duration(days: i * interval * (frequency == 'weekly' ? 7 : 1)),
        );
      } else {
        final month = DateTime(
          next.year,
          next.month - i * interval * (frequency == 'yearly' ? 12 : 1),
        );
        date = DateTime(
          month.year,
          month.month,
          next.day.clamp(1, DateTime(month.year, month.month + 1, 0).day),
          10,
          30,
        );
      }
      if (date.isAfter(today)) continue;
      transactions.add(
        record(
          id == 'demo-salary-plan' && i == 1 ? 'demo-salary' : '$id-paid-$i',
          type,
          minor,
          date,
          '$name - payment ${paid - i + 1}',
          account: account,
          counterAccount: counterAccount,
          category: category,
          source: 'recurring',
          parent: id,
          tags: ['Recurring'],
        ),
      );
    }
  }

  final salaryDue = monthDate(today.day >= 24 ? 1 : 0, 24);
  plan(
    'demo-salary-plan',
    'Monthly salary',
    12500000,
    type: 'income',
    category: 'cat-salary',
    due: salaryDue,
    paid: 30,
    automatic: true,
  );
  plan(
    'demo-rent',
    'Apartment rent',
    2800000,
    category: 'cat-rent-mortgage',
    paid: 30,
  );
  plan(
    'demo-emi',
    'Home loan EMI',
    4200000,
    type: 'loan_repayment',
    counterAccount: 'demo-loan',
    category: 'cat-emi',
    dueInDays: 10,
    paid: 24,
    limit: 72,
  );
  plan(
    'demo-car-emi',
    'Car loan EMI',
    1250000,
    type: 'loan_repayment',
    counterAccount: 'demo-car-loan',
    category: 'cat-emi',
    dueInDays: 8,
    paid: 18,
    limit: 60,
  );
  plan(
    'demo-education-emi',
    'Education loan payment',
    26000,
    type: 'loan_repayment',
    account: 'demo-usd',
    counterAccount: 'demo-education-loan',
    category: 'cat-emi',
    dueInDays: 12,
    paid: 12,
    limit: 84,
  );
  plan(
    'demo-electricity',
    'Electricity bill - overdue',
    280000,
    category: 'cat-electricity',
    dueInDays: -3,
    paid: 24,
  );
  plan(
    'demo-internet',
    'Home internet',
    99900,
    category: 'cat-internet',
    dueInDays: 1,
    paid: 24,
  );
  plan(
    'demo-gym',
    'Gym membership - due today',
    180000,
    category: 'cat-fitness',
    dueInDays: 0,
    paid: 18,
  );
  plan(
    'demo-streaming',
    'Streaming subscription USD',
    1499,
    account: 'demo-usd',
    category: 'cat-streaming',
    dueInDays: 2,
    paid: 18,
  );
  plan(
    'demo-insurance',
    'Annual health insurance',
    1850000,
    category: 'cat-insurance',
    frequency: 'yearly',
    dueInDays: 7,
    paid: 2,
  );
  plan(
    'demo-savings-plan',
    'Emergency fund contribution',
    800000,
    type: 'transfer',
    counterAccount: 'demo-savings',
    category: 'cat-emergency-fund',
    dueInDays: 5,
    paid: 24,
  );
  plan(
    'demo-sip',
    'Monthly index-fund investment',
    500000,
    type: 'transfer',
    counterAccount: 'demo-investment',
    category: 'cat-sip-mutual-funds',
    dueInDays: 6,
    paid: 24,
  );
  plan(
    'demo-card-payment-plan',
    'Credit card bill payment',
    850000,
    type: 'card_payment',
    counterAccount: 'demo-card',
    category: 'cat-credit-card-payment',
    dueInDays: 1,
    paid: 24,
  );
  plan(
    'demo-freelance',
    'Freelance retainer USD',
    65000,
    type: 'income',
    account: 'demo-usd',
    category: 'cat-freelance',
    dueInDays: 12,
    paid: 24,
  );
  plan(
    'demo-rental-income',
    'Rental income',
    2200000,
    type: 'income',
    category: 'cat-rental-income',
    dueInDays: 3,
    paid: 24,
  );
  plan(
    'demo-charity',
    'Monthly charity donation',
    50000,
    category: 'cat-charity',
    dueInDays: 14,
    paid: 18,
  );
  plan(
    'demo-water',
    'Quarterly water bill',
    160000,
    category: 'cat-water',
    interval: 3,
    dueInDays: 9,
    paid: 8,
  );
  plan(
    'demo-school',
    'Education installment',
    650000,
    category: 'cat-education',
    dueInDays: 11,
    paid: 8,
    limit: 18,
  );
  plan(
    'demo-tax',
    'Annual property tax',
    1200000,
    category: 'cat-property-tax',
    frequency: 'yearly',
    dueInDays: 50,
    paid: 2,
  );
  plan(
    'demo-euro-savings',
    'USD to EUR travel savings',
    20000,
    type: 'transfer',
    account: 'demo-usd',
    counterAccount: 'demo-eur',
    category: 'cat-emergency-fund',
    dueInDays: 13,
    paid: 18,
  );
  plan(
    'demo-weekly-meal',
    'Weekly meal delivery',
    95000,
    category: 'cat-food-delivery',
    frequency: 'weekly',
    dueInDays: 2,
    paid: 16,
  );
  plan(
    'demo-paused-yoga',
    'Yoga classes - paused',
    85000,
    category: 'cat-fitness',
    frequency: 'weekly',
    dueInDays: 2,
    paid: 12,
    status: 'paused',
  );
  plan(
    'demo-paused-software',
    'Design software - paused',
    2900,
    account: 'demo-usd',
    category: 'cat-subscriptions',
    dueInDays: 4,
    paid: 10,
    status: 'paused',
  );
  plan(
    'demo-finished-course',
    'Design course - completed',
    700000,
    category: 'cat-education',
    due: monthDate(-2, 15),
    paid: 6,
    limit: 6,
    status: 'finished',
  );
  plan(
    'demo-finished-holiday',
    'Summer holiday - paid',
    7500000,
    category: 'cat-travel-activities',
    frequency: 'once',
    due: monthDate(-5, 10),
    paid: 0,
    limit: 1,
    status: 'finished',
  );
  transactions.add(
    record(
      'demo-holiday-payment',
      'expense',
      7500000,
      monthDate(-5, 10),
      'Summer holiday - final payment',
      category: 'cat-travel-activities',
      source: 'recurring',
      parent: 'demo-finished-holiday',
    ),
  );
  plan(
    'demo-paid-loan-plan',
    'Laptop loan - completed',
    800000,
    type: 'loan_repayment',
    counterAccount: 'demo-paid-loan',
    category: 'cat-emi',
    due: monthDate(-6, 15),
    paid: 12,
    limit: 12,
    status: 'finished',
  );
  plan(
    'demo-tax-overdue',
    'Property tax adjustment - overdue',
    325000,
    category: 'cat-property-tax',
    frequency: 'once',
    dueInDays: -5,
    paid: 0,
    limit: 1,
  );
  plan(
    'demo-invoice-today',
    'Client invoice - due today',
    48000,
    type: 'income',
    account: 'demo-eur',
    category: 'cat-freelance',
    frequency: 'once',
    dueInDays: 0,
    paid: 0,
    limit: 1,
  );
  plan(
    'demo-school-term',
    'School term fees',
    950000,
    category: 'cat-education',
    dueInDays: 20,
    paid: 8,
    endsOn: today.add(const Duration(days: 180)),
  );

  const spending = [
    ('groceries', 'Weekly groceries', 'cat-grocery', 'demo-card', 325000, 3),
    ('dining', 'Dinner with friends', 'cat-dining', 'demo-card', 180000, 7),
    ('market', 'Local market shopping', 'cat-grocery', 'demo-cash', 85000, 6),
    ('coffee', 'Coffee and lunch', 'cat-coffee-cafes', 'demo-cash', 24000, 10),
    ('metro', 'Metro recharge', 'cat-public-transit', 'demo-wallet', 45000, 12),
    ('fuel', 'Fuel and road trip', 'cat-fuel', 'demo-bank', 210000, 14),
    ('health', 'Pharmacy and health', 'cat-pharmacy', 'demo-bank', 68000, 16),
    (
      'shopping',
      'Clothing and essentials',
      'cat-clothing',
      'demo-card',
      260000,
      18,
    ),
    (
      'travel-eur',
      'Europe train ticket',
      'cat-public-transit',
      'demo-eur',
      3200,
      20,
    ),
    ('travel-gbp', 'London cafe', 'cat-coffee-cafes', 'demo-gbp', 1850, 22),
    ('dubai', 'Dubai groceries', 'cat-grocery', 'demo-aed', 17500, 25),
    ('fees', 'Bank service fee', 'cat-bank-fees', 'demo-bank', 15000, 27),
    ('cash-topup', 'Cash withdrawal', 'cat-bills', 'demo-bank', 200000, 28),
  ];
  for (var offset = -29; offset <= 0; offset++) {
    for (final (key, label, category, account, minor, day) in spending) {
      final recent = offset == 0;
      final date = recent && key == 'coffee'
          ? today
          : recent && key == 'groceries'
          ? today.subtract(const Duration(days: 1))
          : monthDate(offset, day);
      if (date.isAfter(today)) continue;
      transactions.add(
        record(
          recent ? 'demo-$key' : 'demo-$key-${date.year}-${date.month}',
          key == 'cash-topup' ? 'transfer' : 'expense',
          minor + (key == 'groceries' ? (-offset % 4) * 12500 : 0),
          date,
          label,
          account: account,
          category: category,
          counterAccount: key == 'cash-topup' ? 'demo-cash' : null,
          source: key == 'groceries' || key == 'shopping' ? 'csv' : 'manual',
          importBatch: key == 'groceries' || key == 'shopping'
              ? 'demo-import'
              : null,
          tags: [key.startsWith('travel') ? 'Travel' : 'Everyday'],
        ),
      );
    }
    if (offset % 3 == 0) {
      transactions.add(
        record(
          'demo-dividend-$offset',
          'income',
          12500,
          monthDate(offset, 1),
          'Quarterly dividend',
          account: 'demo-cad',
          category: 'cat-interest-dividends',
          tags: ['Investments'],
        ),
      );
    }
    final cashbackDate = monthDate(offset, 5);
    if (!cashbackDate.isAfter(today)) {
      transactions.add(
        record(
          'demo-cashback-$offset',
          'income',
          28000,
          cashbackDate,
          'Card cashback',
          category: 'cat-cashback',
          source: 'notification',
        ),
      );
    }
  }
  transactions.addAll([
    record(
      'demo-bills',
      'expense',
      280000,
      today.subtract(const Duration(days: 5)),
      'Electricity top-up',
      category: 'cat-electricity',
    ),
    record(
      'demo-transfer',
      'transfer',
      100000,
      today.subtract(const Duration(days: 4)),
      'Cash withdrawal',
      counterAccount: 'demo-cash',
    ),
    record(
      'demo-refund',
      'income',
      175000,
      today.subtract(const Duration(days: 2)),
      'Shopping refund',
      category: 'cat-refunds',
      source: 'sms',
    ),
    record(
      'demo-bonus',
      'income',
      2500000,
      monthDate(-1, 21),
      'Quarterly performance bonus',
      category: 'cat-bonus',
    ),
    record(
      'demo-skipped-streaming',
      'expense',
      1499,
      monthDate(-2, 14),
      'Streaming - skipped while travelling',
      account: 'demo-usd',
      category: 'cat-streaming',
      status: 'void',
      source: 'recurring',
      parent: 'demo-streaming',
    ),
    record(
      'demo-eur-transfer',
      'transfer',
      120000,
      today.subtract(const Duration(days: 8)),
      'International savings transfer USD to EUR',
      account: 'demo-usd',
      counterAccount: 'demo-eur',
      category: 'cat-emergency-fund',
    ),
    record(
      'demo-paid-card-payment',
      'card_payment',
      45000,
      today.subtract(const Duration(days: 1)),
      'Sterling card bill paid',
      account: 'demo-gbp',
      counterAccount: 'demo-card-paid',
      category: 'cat-credit-card-payment',
    ),
    record(
      'demo-archived-trip',
      'expense',
      4500,
      monthDate(-20, 8),
      'Previous Europe trip',
      account: 'demo-archived',
      category: 'cat-travel-activities',
    ),
  ]);
  CaptureCandidate capture(
    String id,
    String merchant,
    int minor,
    String account,
    String category, {
    String source = 'sms',
    String type = 'expense',
    int hoursAgo = 0,
    String? pair,
    String? counter,
    String? text,
  }) => CaptureCandidate(
    id: id,
    source: source,
    status: 'pending',
    createdAt: now.subtract(Duration(hours: hoursAgo)),
    parsedAmount: money(minor, byId[account]!.currency),
    merchant: merchant,
    transactionType: type,
    suggestedAccountId: account,
    suggestedCounterAccountId: counter,
    suggestedCategoryId: category,
    suggestedCategoryConfidence: 0.92,
    suggestedCategoryReason: 'Demo merchant-to-category match',
    pairedCandidateId: pair,
    rawText:
        text ??
        'DEMO ONLY: ${byId[account]!.name} ${type == 'income' ? 'credited' : 'debited'} '
            '${byId[account]!.currency} ${minor ~/ 100}.${(minor % 100).toString().padLeft(2, '0')} '
            'at $merchant. Fictitious transaction alert.',
  );
  final imports = transactions
      .where((t) => t.importBatchId == 'demo-import')
      .length;
  return emptyLedgerState(
    preferences: LedgerPreferences(
      baseCurrency: 'INR',
      displayCurrency: 'INR',
      enabledCurrencies: inrPerUnit.keys.toList(),
      locale: 'en_IN',
      readNotificationIds: const ['scheduled_soon_demo-gym'],
    ),
  ).copyWith(
    accounts: [
      for (var i = 0; i < accounts.length; i++)
        accounts[i].copyWith(sortOrder: i),
    ],
    transactions: transactions,
    exchangeRates: [
      for (final base in inrPerUnit.keys)
        for (final quote in inrPerUnit.keys)
          if (base != quote)
            ExchangeRateRecord(
              base: base,
              quote: quote,
              rate: inrPerUnit[base]! / inrPerUnit[quote]!,
              asOfDate: today,
              updatedAt: now,
              source: 'Illustrative demo rate',
            ),
    ],
    captureCandidates: [
      capture('demo-capture', 'Fresh Mart', 245000, 'demo-card', 'cat-grocery'),
      capture(
        'demo-capture-salary',
        'Salary credit',
        12500000,
        'demo-bank',
        'cat-salary',
        type: 'income',
        hoursAgo: 1,
      ),
      capture(
        'demo-capture-coffee',
        'Corner Cafe',
        42000,
        'demo-cash',
        'cat-coffee-cafes',
        source: 'receipt',
        hoursAgo: 2,
      ),
      capture(
        'demo-capture-usd',
        'Design Tools USD',
        2900,
        'demo-usd',
        'cat-subscriptions',
        source: 'notification',
        hoursAgo: 3,
      ),
      capture(
        'demo-capture-refund',
        'Store refund',
        175000,
        'demo-bank',
        'cat-refunds',
        type: 'income',
        source: 'notification',
        hoursAgo: 4,
      ),
      capture(
        'demo-capture-transfer-out',
        'Savings transfer debit',
        1000000,
        'demo-bank',
        'cat-emergency-fund',
        pair: 'demo-capture-transfer-in',
        counter: 'demo-savings',
        hoursAgo: 5,
      ),
      capture(
        'demo-capture-transfer-in',
        'Savings transfer credit',
        1000000,
        'demo-savings',
        'cat-emergency-fund',
        type: 'income',
        pair: 'demo-capture-transfer-out',
        counter: 'demo-bank',
        hoursAgo: 5,
      ),
      capture(
        'demo-capture-aed',
        'Dubai Fuel',
        8500,
        'demo-aed',
        'cat-fuel',
        source: 'notification',
        hoursAgo: 6,
      ),
      capture(
        'demo-capture-duplicate',
        'Shopping refund - possible duplicate',
        175000,
        'demo-bank',
        'cat-refunds',
        type: 'income',
        hoursAgo: 48,
      ),
      capture(
        'demo-capture-unmatched',
        'Unknown merchant - review account',
        89900,
        'demo-bank',
        'cat-shopping',
        hoursAgo: 7,
      ).copyWith(
        suggestedCategoryConfidence: 0.35,
        suggestedCategoryReason: 'Uncertain match; please review',
      ),
      CaptureCandidate(
        id: 'demo-capture-no-account',
        source: 'notification',
        status: 'pending',
        createdAt: now.subtract(const Duration(hours: 8)),
        merchant: 'Unrecognized bank alert',
        parsedAmount: money(34900),
        transactionType: 'expense',
        rawText:
            'DEMO ONLY: INR 349.00 debited. Account could not be matched. Select an account before saving.',
      ),
    ],
    importBatches: [
      ImportBatch(
        id: 'demo-import',
        source: 'csv',
        status: 'completed',
        createdAt: today.subtract(const Duration(days: 1)),
        rowCount: imports + 3,
        importedCount: imports,
        duplicateCount: 3,
      ),
    ],
  );
}
