import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/widgets/app_kit.dart';

void main() {
  testWidgets('PremiumRow keeps long option text readable', (tester) async {
    const title = 'A very long settings option title that should wrap cleanly';
    const subtitle =
        'A long description explaining every part of the option without being hidden behind an ellipsis.';
    const meta = 'Long supporting meta text that should also remain visible';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: PremiumRow(
                icon: Icons.settings_outlined,
                title: title,
                subtitle: subtitle,
                meta: meta,
                onTap: () {},
              ),
            ),
          ),
        ),
      ),
    );

    for (final text in [title, subtitle, meta]) {
      final widget = tester.widget<Text>(find.text(text));
      expect(widget.maxLines, isNull);
      expect(widget.overflow, isNull);
    }
  });

  testWidgets('InfoRow keeps long values readable', (tester) async {
    const value =
        'very.long.account.email.address.and.provider.status@example.financial-domain.test';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: InfoRow(
                label: 'Signed in as',
                value: value,
                icon: Icons.account_circle_outlined,
              ),
            ),
          ),
        ),
      ),
    );

    final widget = tester.widget<Text>(find.text(value));
    expect(widget.maxLines, isNull);
    expect(widget.overflow, isNull);
  });
}
