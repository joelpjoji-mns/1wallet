import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../widgets/app_kit.dart';
import 'discovery_controller.dart';
import 'discovery_overlay.dart';

class GuidedEditorOverlay extends ConsumerWidget {
  const GuidedEditorOverlay({
    required this.target,
    required this.feature,
    required this.step,
    required this.title,
    required this.message,
    super.key,
  });

  final GlobalKey target;
  final String feature;
  final int step;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final owner = ref.watch(
      authControllerProvider.select((state) => state.ownerId),
    );
    if (owner == null) return const SizedBox.shrink();
    final progress = ref.watch(discoveryControllerProvider(owner));
    final touringEditor =
        progress.status == DiscoveryStatus.paused && progress.step == step ||
        feature == 'guide-record' &&
            progress.isReplay &&
            progress.status == DiscoveryStatus.completion &&
            progress.step == 1;
    final dismissed = progress.isReplay
        ? progress.replayHintsDismissed.contains(feature)
        : progress.introduced.contains(feature);
    if (!touringEditor || dismissed) {
      return const SizedBox.shrink();
    }
    Future<void> dismiss() async {
      try {
        await ref
            .read(discoveryControllerProvider(owner).notifier)
            .dismissHint(feature);
      } catch (error, stack) {
        debugPrint('Could not save guide preference: $error');
        debugPrintStack(stackTrace: stack);
        if (context.mounted) {
          showAppSnackBar(context, 'Could not save this preference.');
        }
      }
    }

    return DiscoveryOverlay(
      progress: const DiscoveryProgress(status: DiscoveryStatus.active),
      dashboardTarget: target,
      navigationTarget: target,
      actionTarget: target,
      profileTarget: target,
      selectedTab: 0,
      hasAccounts: true,
      onSelectTab: (_) {},
      onStart: () {},
      onPause: () {},
      onFinish: dismiss,
      onPrevious: () {},
      onNext: dismiss,
      onSkipStep: dismiss,
      customTitle: title,
      customDescription: message,
      onCustomDismiss: dismiss,
    );
  }
}
