import 'package:flutter/foundation.dart';

class DiscoveryFeatureStep {
  const DiscoveryFeatureStep(
    this.title,
    this.message,
    this.route,
    this.anchor, {
    this.leaveDraft = false,
    this.requiresTap = false,
  });

  final String title;
  final String message;
  final String route;
  final String anchor;
  final bool leaveDraft;
  final bool requiresTap;
}

class DiscoveryFeatureGuide {
  const DiscoveryFeatureGuide(this.id, this.title, this.steps);
  final String id;
  final String title;
  final List<DiscoveryFeatureStep> steps;
}

const discoveryFeatureGuides = [
  DiscoveryFeatureGuide('planned-payments', 'Plans & recurring payments', [
    DiscoveryFeatureStep(
      'Plan ahead',
      'Plans describe upcoming income, expenses or transfers. Planned amounts are not the same as actual payments. Try the sample below.',
      '/recurring',
      'sample',
    ),
    DiscoveryFeatureStep(
      'Build a real plan',
      'Choose the account, amount, next date and repeating rule. You can inspect this form without saving.',
      '/recurring/new',
      'plan-fields',
    ),
    DiscoveryFeatureStep(
      'Saving makes it real',
      'Save creates scheduled wallet activity. Posted payments stay in history even if you later delete the plan. Continue leaves this unsaved draft.',
      '/recurring/new',
      'save',
      leaveDraft: true,
    ),
  ]),
  DiscoveryFeatureGuide('loans', 'Loans & repayments', [
    DiscoveryFeatureStep(
      'Track what you owe',
      'A loan combines its outstanding balance with repayments. The example is not part of your wallet.',
      '/loans',
      'sample',
    ),
    DiscoveryFeatureStep(
      'Set the loan terms',
      'Enter principal, current balance and repayment terms. An optional scheduled EMI connects this loan to Plans and Calendar.',
      '/loans/new',
      'loan-fields',
    ),
    DiscoveryFeatureStep(
      'Review before saving',
      'Saving creates a real loan account and any repayment schedule you selected. This tour never presses Save for you.',
      '/loans/new',
      'save',
      leaveDraft: true,
    ),
  ]),
  DiscoveryFeatureGuide('loan-forecast', 'Forecast & extra repayments', [
    DiscoveryFeatureStep(
      'What if you paid extra?',
      'Forecast uses your loans, liquid balances and planned activity. Try an extra payment in the isolated example; it does not change your accounts.',
      '/loans/forecast',
      'sample',
    ),
    DiscoveryFeatureStep(
      'Your real forecast',
      'Emergency cash and extra-allocation controls affect your saved forecast preferences. The projection is an estimate, not a transaction or a promise.',
      '/loans/forecast',
      'forecast-controls',
    ),
  ]),
  DiscoveryFeatureGuide('account-details', 'Accounts, credentials & matching', [
    DiscoveryFeatureStep(
      'Open an account',
      'Account cards connect balances, records and account settings. We will inspect a real account without changing it.',
      '/accounts',
      'accounts-search',
    ),
    DiscoveryFeatureStep(
      'Account settings',
      'Check currency, opening balance and visibility. Secure Details is where bank or card credentials live.',
      '@account',
      'account-name',
    ),
    DiscoveryFeatureStep(
      'Credentials stay encrypted',
      'Enter a bank account or card number here. Saving encrypts the details and records its final four digits for capture matching. Never enter sample credentials into your real account.',
      '@secure',
      'credentials',
    ),
    DiscoveryFeatureStep(
      'Save the suffix, improve matching',
      'The last four digits help SMS and notification captures suggest the right account. Save only if these are your own correct details; continue leaves edits unsaved.',
      '@secure',
      'save',
      leaveDraft: true,
    ),
  ]),
  DiscoveryFeatureGuide('review-inbox', 'Review, account matching & alerts', [
    DiscoveryFeatureStep(
      'Message to account',
      'Try the sample: the real parser extracts an amount and account suffix, then the real matcher chooses a sample account. No capture is imported.',
      '/review',
      'sample',
    ),
    DiscoveryFeatureStep(
      'Review before posting',
      'Check merchant, amount, category and suggested account. If suffixes are absent or ambiguous, choose the account yourself. Approving creates a real record; dismissing does not.',
      '/review',
      'inbox',
    ),
    DiscoveryFeatureStep(
      'Notifications belong here too',
      'The same inbox also contains reminders and account alerts. Reading an alert is different from approving a captured transaction. Capture requires optional device permissions.',
      '/review',
      'capture-settings',
    ),
  ]),
  DiscoveryFeatureGuide('notification-capture', 'Notification & SMS capture', [
    DiscoveryFeatureStep(
      'Choose what to capture',
      'Enable notification access only if you want it, then choose supported banking apps. SMS capture has its own permission. The tour never grants access.',
      '/notification-capture',
      'screen',
    ),
    DiscoveryFeatureStep(
      'Match, then review',
      'Set the correct bank or card number in Secure Details so its final four digits can identify the account. Captured suggestions are reviewed in the inbox before they become records.',
      '/review',
      'sample',
    ),
  ]),
  DiscoveryFeatureGuide('calendar-days', 'Calendar & day details', [
    DiscoveryFeatureStep(
      'Tap the highlighted date',
      'Open a real day. Its sheet brings posted records, upcoming plans and the projected end-of-day balance together.',
      '/?tab=2',
      'calendar-day',
      requiresTap: true,
    ),
    DiscoveryFeatureStep(
      'A day in detail',
      'This is the actual day sheet. Tap a posted record for details, or a forecast occurrence to edit its recurring plan. Empty days are valid too.',
      '/?tab=2',
      'calendar-sheet',
    ),
  ]),
  DiscoveryFeatureGuide('statement-import', 'Statement import', [
    DiscoveryFeatureStep(
      'Import with a review',
      'Choose a supported PDF or CSV statement, inspect the parsed rows and check the account before importing. Uploading or saving real data is always your choice.',
      '/import-statement',
      'screen',
    ),
  ]),
  DiscoveryFeatureGuide('home-widgets', 'Dashboard widgets', [
    DiscoveryFeatureStep(
      'Build your dashboard',
      'Choose the cards that matter to you. Widget changes personalize your real Home screen; they do not create transactions.',
      '/widgets',
      'screen',
    ),
  ]),
  DiscoveryFeatureGuide('personalization', 'Privacy, appearance & backup', [
    DiscoveryFeatureStep(
      'Your preferences',
      'Set currency, privacy and appearance here. Backup protects the wallet; keep its encryption password safe. Every guide is available here whenever you need it.',
      '/settings',
      'screen',
    ),
  ]),
];

DiscoveryFeatureGuide? discoveryFeatureGuide(String id) {
  for (final guide in discoveryFeatureGuides) {
    if (guide.id == id) return guide;
  }
  return null;
}

Iterable<DiscoveryFeatureGuide> get availableDiscoveryFeatureGuides =>
    discoveryFeatureGuides.where(
      (guide) =>
          guide.id != 'notification-capture' ||
          (!kIsWeb && defaultTargetPlatform == TargetPlatform.android),
    );
