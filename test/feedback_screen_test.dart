import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/features/settings/feedback_screen.dart';

void main() {
  testWidgets(
    'renders FeedbackScreen with all input elements and contact info',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: FeedbackScreen())),
      );
      await tester.pumpAndSettle();

      expect(find.text('Feedback & Support'), findsOneWidget);
      expect(find.text('Connect with Joel'), findsOneWidget);
      expect(find.text('Category'), findsOneWidget);
      expect(find.text('Bug Report'), findsOneWidget);
      expect(find.text('Feedback Details'), findsOneWidget);
      expect(find.text('Subject'), findsOneWidget);
      expect(find.text('Screenshots & Screen Recordings'), findsOneWidget);
      expect(find.text('Include device & app logs'), findsOneWidget);
      expect(find.text('Send email'), findsOneWidget);
      expect(find.text('Copy'), findsOneWidget);
    },
  );
}
