import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'account_deletion_controller.dart';
import '../../cloud_sync/cloud_sync_controller.dart';
import '../../design/tokens.dart';
import '../common/route_scaffold.dart';

enum _StepState { pending, active, done, failed }

class AccountDeletionScreen extends ConsumerWidget {
  const AccountDeletionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountDeletionControllerProvider);
    final cloud = ref.watch(cloudSyncControllerProvider);
    final observed = cloud.accountDeletionPending && !state.operationPending;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final controller = ref.read(accountDeletionControllerProvider.notifier);

    final stage = state.stage;
    final failed = stage == AccountDeletionStage.error;
    final succeeded = stage == AccountDeletionStage.success;

    final (IconData icon, Color tone, String title) = switch (stage) {
      _ when observed => (
        Icons.devices_other_outlined,
        scheme.tertiary,
        'Deleting from another device',
      ),
      AccountDeletionStage.success => (
        Icons.check_circle_outline_rounded,
        scheme.primary,
        'Account deleted',
      ),
      AccountDeletionStage.error => (
        Icons.error_outline_rounded,
        scheme.error,
        "Deletion didn't finish",
      ),
      AccountDeletionStage.idle => (
        Icons.delete_forever_outlined,
        scheme.error,
        state.operationPending ? 'Cleanup paused' : 'Delete account',
      ),
      _ => (Icons.delete_sweep_outlined, scheme.error, 'Deleting your account'),
    };

    final message = observed
        ? cloud.error ??
              'Wallet access and capture are paused while the server confirms '
                  'the deletion.'
        : switch (stage) {
            AccountDeletionStage.idle =>
              state.operationPending
                  ? 'A deletion was started but not finished. Resume to '
                        'complete cleanup.'
                  : 'Permanently erase your cloud wallet, sign-in and the data '
                        'on this device.',
            _ => state.statusMessage,
          };

    final cloudDone =
        state.remoteComplete ||
        succeeded ||
        stage == AccountDeletionStage.deletingCloudAccount ||
        stage == AccountDeletionStage.deletingLocalData;
    final credentialsDone =
        state.remoteComplete ||
        succeeded ||
        stage == AccountDeletionStage.deletingLocalData;
    final localDone = state.localComplete || succeeded;

    _StepState stepState({
      required bool done,
      required bool active,
      required bool firstOpen,
    }) {
      if (done) return _StepState.done;
      if (active) return _StepState.active;
      if (failed && firstOpen) return _StepState.failed;
      return _StepState.pending;
    }

    final steps = [
      (
        'Cloud data and backups',
        stepState(
          done: cloudDone,
          active: stage == AccountDeletionStage.deletingCloudData,
          firstOpen: true,
        ),
      ),
      (
        'Sign-in credentials',
        stepState(
          done: credentialsDone,
          active: stage == AccountDeletionStage.deletingCloudAccount,
          firstOpen: cloudDone,
        ),
      ),
      (
        'Data on this device',
        stepState(
          done: localDone,
          active: stage == AccountDeletionStage.deletingLocalData,
          firstOpen: credentialsDone,
        ),
      ),
    ];

    final resume = state.operationPending && !state.isBusy;
    final showAction = !observed && !succeeded;

    return RouteScaffold(
      title: 'Account deletion',
      automaticallyImplyLeading: false,
      hasDrawer: false,
      scrollView: ListView(
        primary: false,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: tone.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border: Border.all(color: tone.withValues(alpha: 0.32)),
              ),
              child: state.isBusy
                  ? Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: tone,
                      ),
                    )
                  : Icon(icon, size: 34, color: tone),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            title,
            textAlign: TextAlign.center,
            style: textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          _Panel(
            child: Column(
              children: [
                for (final (index, step) in steps.indexed) ...[
                  if (index > 0) const SizedBox(height: AppSpacing.sm),
                  _StepRow(label: step.$1, state: step.$2),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _Panel(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Cloud erasure and cleanup of this device are verified '
                    'separately. Exported copies and disconnected devices may '
                    'still retain data.',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (showAction) ...[
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              height: AppSizes.ctaHeight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError,
                ),
                onPressed: state.isBusy
                    ? null
                    : resume
                    ? controller.resumePendingDeletion
                    : controller.deleteAccountAndAllData,
                icon: Icon(
                  resume || failed
                      ? Icons.refresh_rounded
                      : Icons.delete_forever_outlined,
                ),
                label: Text(
                  state.isBusy
                      ? 'Deleting…'
                      : resume
                      ? 'Resume cleanup'
                      : failed
                      ? 'Retry deletion'
                      : 'Delete account',
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: child,
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({required this.label, required this.state});

  final String label;
  final _StepState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final (Color color, String caption) = switch (state) {
      _StepState.done => (scheme.primary, 'Done'),
      _StepState.active => (scheme.tertiary, 'In progress'),
      _StepState.failed => (scheme.error, 'Failed'),
      _StepState.pending => (scheme.onSurfaceVariant, 'Waiting'),
    };
    final Widget leading = switch (state) {
      _StepState.active => SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      ),
      _StepState.done => Icon(
        Icons.check_circle_rounded,
        size: 20,
        color: color,
      ),
      _StepState.failed => Icon(Icons.cancel_rounded, size: 20, color: color),
      _StepState.pending => Icon(
        Icons.radio_button_unchecked_rounded,
        size: 20,
        color: color,
      ),
    };
    return Row(
      children: [
        SizedBox.square(dimension: 24, child: Center(child: leading)),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            label,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        Text(
          caption,
          style: textTheme.labelSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
