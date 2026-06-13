import 'dart:convert';
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
