import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

void main() {
  testWidgets('EmptyState is centered within its parent container', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: AppTopFadeMask(
              child: EmptyState(
                icon: Icons.search_off_rounded,
                title: 'No matching transactions',
                body: 'Clear filters to see the full ledger.',
                actionLabel: 'Clear filters',
                onAction: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final titleFinder = find.text('No matching transactions');
    expect(titleFinder, findsOneWidget);

    final emptyStateFinder = find.byType(EmptyState);
    final emptyStateCenter = tester.getCenter(emptyStateFinder);
    
    // Parent center is (400, 300)
    expect(emptyStateCenter.dx, equals(400.0));
    expect(emptyStateCenter.dy, equals(300.0));

    // Clear filters uses filter_alt_off_rounded instead of add_rounded
    final clearIconFinder = find.byIcon(Icons.filter_alt_off_rounded);
    expect(clearIconFinder, findsOneWidget);
  });

  testWidgets('EmptyState supports back action icon inference', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EmptyState(
            icon: Icons.wallet_outlined,
            title: 'Not found',
            body: 'Item not found.',
            actionLabel: 'Back home',
            onAction: () {},
          ),
        ),
      ),
    );

    final backIconFinder = find.byIcon(Icons.arrow_back_rounded);
    expect(backIconFinder, findsOneWidget);
  });
}
