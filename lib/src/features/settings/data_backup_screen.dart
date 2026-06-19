import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    if (_latestAutoBackup == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore auto-backup?'),
        content: const Text(
            'This will overwrite your current local data with the snapshot from this auto-backup file. Are you sure?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restore', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await ref.read(ledgerProvider.notifier).restoreFromAutoBackup(_latestAutoBackup!);
      if (!mounted) return;
      setState(() => _status = 'Restored successfully from auto-backup.');
      _showBackupMessage('Auto-backup restored successfully.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Auto-backup restore failed: $e');
      _showBackupMessage('Auto-backup restore failed.');
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
                onPressed: _restoreFromAutoBackup,
                icon: const Icon(Icons.history_toggle_off_rounded),
                label: const Text('Restore latest auto-backup'),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.tertiary,
                  foregroundColor: Theme.of(context).colorScheme.onTertiary,
                ),
              ),
            ),
          ],
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Export',
            subtitle:
                'Generate a portable 1Wallet archive and save it to your device.',
            child: FilledButton.icon(
              onPressed: _generateAndSaveArchive,
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
              onPressed: _pickAndRestoreArchive,
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
                  label: 'Budgets',
                  value: '${state.budgets.length}',
                  icon: Icons.donut_large_outlined,
                ),
                InfoRow(
                  label: 'Goals',
                  value: '${state.goals.length}',
                  icon: Icons.flag_outlined,
                ),
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
    final archive = ref.read(ledgerProvider.notifier).exportArchive();

    try {
      final outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save 1Wallet Backup',
        fileName: '1wallet_backup.onewallet',
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
    }
  }

  Future<void> _pickAndRestoreArchive() async {
    try {
      final file = await pickTextFile(
        allowedExtensions: const ['json', 'txt', 'onewallet'],
      );
      if (file == null) {
        _showBackupMessage('Archive file selection cancelled.');
        return;
      }

      await ref.read(ledgerProvider.notifier).importArchive(file.text);
      if (!mounted) return;
      setState(() => _status = 'Restored successfully from ${file.name}.');
      _showBackupMessage('Archive restored successfully.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Restore failed: $error');
      _showBackupMessage('Archive restore failed.');
    }
  }

  void _showBackupMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}
