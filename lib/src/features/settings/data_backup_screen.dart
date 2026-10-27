import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/auth_controller.dart';
import '../../cloud_sync/cloud_sync_controller.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../common/file_picker_utils.dart';
import '../common/route_scaffold.dart';

class DataBackupScreen extends ConsumerStatefulWidget {
  const DataBackupScreen({super.key});

  @override
  ConsumerState<DataBackupScreen> createState() => _DataBackupScreenState();
}

class _DataBackupScreenState extends ConsumerState<DataBackupScreen> {
  String? _status;
  File? _latestAutoBackup;
  DateTime? _latestAutoBackupTime;
  // Guards against rapid double-taps opening two overlapping save/restore
  // flows (e.g. two save-file dialogs, or a restore racing another restore).
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _checkLatestAutoBackup();
  }

  Future<void> _checkLatestAutoBackup() async {
    final notifier = ref.read(ledgerProvider.notifier);
    final file = await notifier.getLatestAutoBackupFile();
    if (file != null) {
      final stat = await file.stat();
      if (mounted) {
        setState(() {
          _latestAutoBackup = file;
          _latestAutoBackupTime = stat.modified;
        });
      }
    }
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _restoreFromAutoBackup() async {
    if (_latestAutoBackup == null || _busy) return;
    setState(() => _busy = true);
    final confirm = await showAppConfirmDialog(
      context,
      title: 'Restore auto-backup?',
      message:
          'This replaces the wallet on this device and, when signed in, the cloud wallet used on your other devices. '
          'The backup may be older than your current data. Continue?',
      confirmLabel: 'Restore',
      destructive: true,
    );
    if (!confirm || !mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    try {
      await ref
          .read(ledgerProvider.notifier)
          .restoreFromAutoBackup(_latestAutoBackup!);
      if (!mounted) return;
      await _reportRestore();
    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('Restore rejected')) {
        final isDifferentAccount = e.toString().contains('different account');
        final confirmForce = await showAppConfirmDialog(
          context,
          title: isDifferentAccount
              ? 'Warning: Different Account Backup'
              : 'Warning: Older Backup',
          message: isDifferentAccount
              ? 'This backup belongs to a different user account. Restoring it will replace your current wallet and sync that data into your signed-in account. Are you sure?'
              : 'Your current local data is newer or has more transactions than this auto-backup. '
                    'Are you sure you want to overwrite your current data?',
          confirmLabel: 'Force Restore',
          destructive: true,
        );
        if (confirmForce && mounted) {
          try {
            await ref
                .read(ledgerProvider.notifier)
                .restoreFromAutoBackup(_latestAutoBackup!, force: true);
            if (!mounted) return;
            await _reportRestore();
            return;
          } catch (forceError) {
            if (!mounted) return;
            setState(() => _status = 'Force restore failed: $forceError');
            _showBackupMessage('Auto-backup restore failed.');
            return;
          }
        }
      }
      setState(() => _status = 'Auto-backup restore failed: $e');
      _showBackupMessage('Auto-backup restore failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final locale = state.preferences.locale;
    return RouteScaffold(
      title: 'Data backup',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Ledger snapshot',
            subtitle:
                'Export a checksum-protected local archive or restore one from a file.',
            child: Row(
              children: [
                Expanded(
                  child: MetricTile(
                    label: 'Accounts',
                    value: '${state.accounts.length}',
                    icon: Icons.account_balance_wallet_outlined,
                    compact: true,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: MetricTile(
                    label: 'Records',
                    value: '${state.transactions.length}',
                    icon: Icons.receipt_long_outlined,
                    compact: true,
                  ),
                ),
              ],
            ),
          ),
          if (_latestAutoBackup != null) ...[
            const Gap(AppSpacing.lg),
            SectionCard(
              title: 'Auto-Backup Found',
              subtitle:
                  'A recent automatic local backup was found:\nLast modified: ${_formatDateTime(_latestAutoBackupTime!)}\nPath: ${_latestAutoBackup!.path}',
              child: FilledButton.icon(
                onPressed: _busy ? null : _restoreFromAutoBackup,
                icon: const Icon(Icons.history_toggle_off_rounded),
                label: const Text('Restore latest auto-backup'),
              ),
            ),
          ],
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Export',
            subtitle:
                'Generate a portable 1Wallet archive and save it to your device.',
            child: FilledButton.icon(
              onPressed: _busy ? null : _generateAndSaveArchive,
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Save to file'),
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Restore',
            subtitle:
                'Pick an archive file from your device. Checksum validation runs before replacing local data.',
            child: FilledButton.tonalIcon(
              onPressed: _busy ? null : _pickAndRestoreArchive,
              icon: const Icon(Icons.restore_outlined),
              label: const Text('Restore from file'),
            ),
          ),
          if (_status != null) ...[
            const Gap(AppSpacing.lg),
            SectionCard(title: 'Status', child: Text(_status!)),
          ],
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Current summary',
            child: Column(
              children: [
                InfoRow(
                  label: 'Capture candidates',
                  value: '${state.captureCandidates.length}',
                  icon: Icons.fact_check_outlined,
                ),
                InfoRow(
                  label: 'Display currency',
                  value: state.preferences.displayCurrency,
                  icon: Icons.currency_exchange_outlined,
                ),
                InfoRow(
                  label: 'Locale',
                  value: locale,
                  icon: Icons.language_outlined,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _generateAndSaveArchive() async {
    if (_busy) return;
    setState(() => _busy = true);
    final notifier = ref.read(ledgerProvider.notifier);
    final defaultFileName = notifier.defaultManualBackupFileName();

    try {
      final passphrase = await showDialog<String>(
        context: context,
        builder: (_) => const _BackupPassphraseDialog(exporting: true),
      );
      if (passphrase == null || !mounted) return;
      final owner = ref.read(ledgerProvider).userId;
      setState(
        () => _status =
            'Encrypting backup. Keep the app open until the save dialog appears.',
      );
      final archive = await notifier.exportPortableBackup(passphrase);
      if (!mounted) return;
      if (ref.read(ledgerProvider).userId != owner) {
        throw StateError('The wallet session changed during export.');
      }
      final outputFile = await FilePicker.saveFile(
        dialogTitle: 'Save 1Wallet Backup',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['onewallet', 'json'],
        bytes: Uint8List.fromList(utf8.encode(archive)),
      );

      if (outputFile == null) {
        _showBackupMessage('Save cancelled.');
        return;
      }

      if (!mounted) return;
      setState(() => _status = 'Archive saved successfully.');
      _showBackupMessage('Archive saved successfully.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Failed to save archive: $e');
      _showBackupMessage('Failed to save archive.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndRestoreArchive() async {
    if (_busy) return;
    setState(() => _busy = true);
    String? fileText;
    String? passphrase;
    bool replacementConfirmed = false;
    try {
      final file = await pickTextFile(
        allowedExtensions: const ['json', 'txt', 'onewallet'],
      );
      if (file == null) {
        _showBackupMessage('Archive file selection cancelled.');
        return;
      }
      fileText = file.text;
      if (!mounted) return;
      if (!fileText.startsWith('v2:')) {
        final envelope = jsonDecode(fileText);
        if (envelope is Map &&
            envelope['format'] == 'onewallet.encrypted.backup') {
          passphrase = await showDialog<String>(
            context: context,
            builder: (_) => const _BackupPassphraseDialog(exporting: false),
          );
          if (passphrase == null || !mounted) return;
        } else {
          final confirmed = await showAppConfirmDialog(
            context,
            title: 'Import legacy plaintext backup?',
            message:
                'This older backup is not encrypted. Import only a file you trust. '
                'After validation it replaces this device\'s wallet and the cloud wallet used on other devices.',
            confirmLabel: 'Import',
          );
          if (!confirmed || !mounted) return;
          replacementConfirmed = true;
        }
      }
      if (!replacementConfirmed && !await _confirmWalletReplacement()) return;
      if (!mounted) return;
      await ref
          .read(ledgerProvider.notifier)
          .importArchive(fileText, passphrase: passphrase);
      if (!mounted) return;
      await _reportRestore();
    } catch (error) {
      if (!mounted) return;
      if (error.toString().contains('Restore rejected')) {
        final isDifferentAccount = error.toString().contains(
          'different account',
        );
        final confirm = await showAppConfirmDialog(
          context,
          title: isDifferentAccount
              ? 'Warning: Different Account Backup'
              : 'Warning: Older Backup',
          message: isDifferentAccount
              ? 'This backup belongs to a different user account. Restoring it will replace your current wallet and sync that data into your signed-in account. Are you sure?'
              : 'Your current local data is newer or has more transactions than this backup. '
                    'Are you sure you want to overwrite your current data?',
          confirmLabel: 'Force Restore',
          destructive: true,
        );
        if (confirm && mounted && fileText != null) {
          try {
            await ref
                .read(ledgerProvider.notifier)
                .importArchive(fileText, force: true, passphrase: passphrase);
            if (!mounted) return;
            await _reportRestore();
            return;
          } catch (e) {
            if (!mounted) return;
            setState(() => _status = 'Force restore failed: $e');
            _showBackupMessage('Archive restore failed.');
            return;
          }
        }
      }
      setState(() => _status = 'Restore failed: $error');
      _showBackupMessage('Archive restore failed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showBackupMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  Future<bool> _confirmWalletReplacement() => showAppConfirmDialog(
    context,
    title: 'Replace local and cloud wallet?',
    message:
        'Once validation succeeds, this backup replaces the wallet on this device '
        'and, when signed in, the cloud wallet used on your other devices. '
        'Cancel if you only want to inspect the file.',
    confirmLabel: 'Replace wallet',
  );

  Future<void> _reportRestore() async {
    if (ref.read(authControllerProvider).isLocalOnly) {
      const message = 'Backup restored on this device.';
      setState(() => _status = message);
      _showBackupMessage(message);
      return;
    }
    final sync = ref.read(cloudSyncControllerProvider.notifier);
    final result = await sync.overwriteCloudWithLocal();
    if (!mounted) return;
    final newer =
        result.localRevision != null &&
        ref.read(ledgerProvider).localRevision != result.localRevision;
    final message = switch (result.outcome) {
      CloudWriteOutcome.uploaded =>
        newer
            ? 'Backup restored and uploaded. Newer edits are still pending.'
            : 'Backup restored and synced to cloud.',
      CloudWriteOutcome.deferred =>
        'Backup restored locally. Cloud sync is pending.',
      CloudWriteOutcome.unavailable =>
        'Backup restored locally. Sign in to enable cloud backup.',
      CloudWriteOutcome.failed =>
        'Backup restored locally. Cloud sync failed; open Sync to retry.',
    };
    setState(() => _status = message);
    _showBackupMessage(message);
  }
}

class _BackupPassphraseDialog extends StatefulWidget {
  const _BackupPassphraseDialog({required this.exporting});
  final bool exporting;
  @override
  State<_BackupPassphraseDialog> createState() =>
      _BackupPassphraseDialogState();
}

class _BackupPassphraseDialogState extends State<_BackupPassphraseDialog> {
  final _passphrase = TextEditingController();
  final _confirmation = TextEditingController();
  String? _error;
  @override
  void dispose() {
    _passphrase.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.exporting ? 'Protect your backup' : 'Unlock backup'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Keep this passphrase safely. It cannot be recovered or reset.',
        ),
        TextField(
          controller: _passphrase,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Backup passphrase'),
        ),
        if (widget.exporting)
          TextField(
            controller: _confirmation,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Confirm passphrase'),
          ),
        if (_error != null) Text(_error!),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_passphrase.text.isEmpty ||
              (widget.exporting && _passphrase.text != _confirmation.text)) {
            setState(
              () => _error = 'Enter a passphrase and matching confirmation.',
            );
            return;
          }
          Navigator.pop(context, _passphrase.text);
        },
        child: Text(widget.exporting ? 'Encrypt backup' : 'Unlock'),
      ),
    ],
  );
}
