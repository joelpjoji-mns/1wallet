import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../design/tokens.dart';
import '../../offline_mode/offline_mode_controller.dart';
import '../../widgets/app_kit.dart';
import '../launch/brand_widgets.dart';

/// Explains offline mode and requires an explicit acknowledgement before the
/// device switches to a wallet that lives only on this device.
Future<void> showOfflineModeSheet(BuildContext context) {
  return showAppSheet<void>(
    context: context,
    builder: (_) => const OfflineModeSheet(),
  );
}

class OfflineModeSheet extends ConsumerStatefulWidget {
  const OfflineModeSheet({super.key});

  static const acknowledgeKey = Key('offline-mode-acknowledge');
  static const confirmKey = Key('offline-mode-confirm');

  @override
  ConsumerState<OfflineModeSheet> createState() => _OfflineModeSheetState();
}

class _OfflineModeSheetState extends ConsumerState<OfflineModeSheet> {
  bool _acknowledged = false;
  bool _busy = false;
  String? _error;

  Future<void> _continueOffline() async {
    if (!_acknowledged || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await ref
        .read(offlineModeControllerProvider.notifier)
        .enterOfflineMode();
    if (!mounted) return;
    switch (result) {
      case OfflineEntryResult.entered:
        Navigator.of(context).maybePop();
      case OfflineEntryResult.walletBelongsToAccount:
        setState(() {
          _busy = false;
          _error =
              'This device still holds a wallet linked to a Google account. '
              'Sign in with Google to open it. To use offline mode instead, '
              'sign in and then sign out first.';
        });
      case OfflineEntryResult.failed:
        setState(() {
          _busy = false;
          _error = 'Could not switch to offline mode. Please try again.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: BrandFrostedPanel(
          borderRadius: AppRadii.xl,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.phonelink_lock_outlined, color: scheme.primary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Use 1Wallet offline',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const _Point(
                  icon: Icons.smartphone_outlined,
                  text:
                      'Your wallet is kept only in this app\'s private storage on '
                      'this device. No Google account is needed.',
                ),
                const _Point(
                  icon: Icons.cloud_off_outlined,
                  text:
                      'Nothing is uploaded and there is no cloud backup or '
                      'sync with your other devices.',
                ),
                const _Point(
                  icon: Icons.save_alt_outlined,
                  text:
                      'You own your backups: export an encrypted backup file '
                      'from Settings › Data backup and keep it somewhere safe.',
                ),
                const _Point(
                  icon: Icons.cloud_upload_outlined,
                  text:
                      'You can turn on Google backup & sync later from '
                      'Settings without losing your data.',
                ),
                _Point(
                  icon: Icons.warning_amber_rounded,
                  color: scheme.error,
                  text:
                      'If you uninstall the app, clear its data or lose this '
                      'device without a backup, your wallet cannot be recovered.',
                ),
                const SizedBox(height: AppSpacing.xs),
                CheckboxListTile(
                  key: OfflineModeSheet.acknowledgeKey,
                  value: _acknowledged,
                  onChanged: _busy
                      ? null
                      : (value) =>
                            setState(() => _acknowledged = value ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'I understand my data stays only on this device',
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                    child: Text(_error!, style: TextStyle(color: scheme.error)),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  key: OfflineModeSheet.confirmKey,
                  onPressed: _acknowledged && !_busy ? _continueOffline : null,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_outline_rounded),
                  label: const Text('Continue offline'),
                ),
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color ?? scheme.primary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color ?? scheme.onSurface.withValues(alpha: 0.8),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
