import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';

class CaptureSettingsScreen extends StatelessWidget {
  const CaptureSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return RouteScaffold(
      title: 'Auto-capture settings',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionCard(
            title: 'Automated Capture',
            subtitle: 'Configure automated draft creation from incoming messages and notifications.',
            compact: true,
            child: SizedBox(),
          ),
          const Gap(AppSpacing.lg),
          PremiumRow(
            icon: Icons.sms_outlined,
            title: 'SMS Capture',
            subtitle: 'Paste a bank or card message and queue a review draft',
            onTap: () => context.push('/import-sms'),
          ),
          const SizedBox(height: AppSpacing.sm),
          PremiumRow(
            icon: Icons.notifications_active_outlined,
            title: 'Notification Capture',
            subtitle: 'Turn incoming app notifications into review drafts',
            onTap: () => context.push('/notification-capture'),
          ),
        ],
      ),
    );
  }
}
