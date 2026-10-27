import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'account_deletion_controller.dart';
import '../../cloud_sync/cloud_sync_controller.dart';

class AccountDeletionScreen extends ConsumerWidget {
  const AccountDeletionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(accountDeletionControllerProvider);
    final cloud = ref.watch(cloudSyncControllerProvider);
    final observed = cloud.accountDeletionPending && !state.operationPending;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account deletion'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (state.isBusy) const CircularProgressIndicator(),
              const SizedBox(height: 16),
              if (state.operationPending && !state.isBusy)
                TextButton(
                  onPressed: () => ref
                      .read(accountDeletionControllerProvider.notifier)
                      .resumePendingDeletion(),
                  child: const Text('Resume cleanup'),
                ),
              Text(
                observed
                    ? cloud.error ??
                          'This account is being deleted from another device. '
                              'Wallet access and capture are paused while server completion is verified.'
                    : state.statusMessage,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                'Cloud erasure and cleanup of this device are verified separately. '
                'Exported copies and disconnected devices may still retain data.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: state.isBusy || observed
                    ? null
                    : () => ref
                          .read(accountDeletionControllerProvider.notifier)
                          .deleteAccountAndAllData(),
                child: const Text('Retry deletion'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
