import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:one_wallet_flutter/src/data/ledger_codec.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/features/home/home_async_providers.dart';
import 'package:one_wallet_flutter/src/features/home/home_dashboard_selectors.dart';
import 'package:one_wallet_flutter/src/features/home/home_widgets.dart';

import 'test_harness.dart';

/// Covers the balance trend widget's async edge cases: the transient loading
/// state, a zero-account/zero-transaction ledger, and a computation failure —
/// the latter must be surfaced distinctly instead of silently collapsing into
/// the "no data" empty state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows a preparing placeholder while trends are loading', (
    tester,
  ) async {
    final state = _ledger();

    await tester.pumpWidget(_wrap(state, overrides: const []));
    // Only pump one frame: the underlying FutureProviders run via `compute`
    // (a real isolate hop), so immediately after the first frame they must
    // still be loading.
    await tester.pump();

    expect(find.text('Preparing balance trend...'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets(
    'renders a flat trend chart (not an error) for a brand new ledger with '
    'no accounts or transactions',
    (tester) async {
      final state = _ledger();

      // Override the trend providers to resolve with the same pure
      // computation the real providers use, but without a real `compute()`
      // isolate hop, so the test is fast and deterministic while still
      // exercising the widget's rendering of resolved (non-error,
      // non-loading) async data.
      await tester.pumpWidget(
        _wrap(
          state,
          overrides: [
            homeBalanceTrendProvider.overrideWith(
              (ref, args) =>
                  balanceTrendForRange(state, start: args.start, end: args.end),
            ),
            homeBalanceFutureTrendProvider.overrideWith(
              (ref, args) => balanceFutureTrendForRange(
                state,
                start: args.start,
                end: args.end,
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // A zero-account/zero-transaction ledger still yields a valid (flat,
      // zero-balance) trend series, so it must render the chart rather than
      // the loading placeholder or an error.
      expect(find.text('Preparing balance trend...'), findsNothing);
      expect(find.text('Could not load balance trend'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shows a distinct error message when the trend computation fails, '
    'instead of silently looking like empty data',
    (tester) async {
      final state = _ledger();

      await tester.pumpWidget(
        _wrap(
          state,
          overrides: [
            homeBalanceTrendProvider.overrideWith(
              (ref, args) async => throw Exception('boom'),
            ),
            homeBalanceFutureTrendProvider.overrideWith(
              (ref, args) async => throw Exception('boom'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not load balance trend'), findsOneWidget);
      expect(find.text('No data for this period'), findsNothing);
      expect(find.text('Preparing balance trend...'), findsNothing);
    },
  );
}

Widget _wrap(LedgerState state, {required List<Override> overrides}) {
  return ProviderScope(
    overrides: [...authenticatedSampleOverrides(ledger: state), ...overrides],
    child: MaterialApp(
      home: Scaffold(body: BalanceTrendHomeWidget(state: state)),
    ),
  );
}

LedgerState _ledger() {
  return LedgerState(
    version: currentLedgerStateVersion,
    userId: 'test-user',
    preferences: const LedgerPreferences(),
    accounts: const [],
    categories: const [],
    transactions: const [],
    captureCandidates: const [],
  );
}
