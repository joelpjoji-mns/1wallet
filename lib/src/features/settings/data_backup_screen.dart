import 'package:flutter/material.dart';
import '../common/route_scaffold.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../widgets/app_kit.dart';
import '../common/file_picker_utils.dart';

class DataBackupScreen extends ConsumerStatefulWidget {
  const DataBackupScreen({super.key});

  @override
  ConsumerState<DataBackupScreen> createState() => _DataBackupScreenState();
}

class _DataBackupScreenState extends ConsumerState<DataBackupScreen> {
  final _archiveController = TextEditingController();
  String? _status;

  @override
  void dispose() {
    _archiveController.dispose();
    super.dispose();
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
                'Export a checksum-protected local archive or restore one by pasting JSON.',
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
            subtitle: 'Generate a portable 1Wallet archive and copy it.',
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                FilledButton.icon(
                  onPressed: _generateArchive,
                  icon: const Icon(Icons.file_download_outlined),
                  label: const Text('Generate archive'),
                ),
                FilledButton.tonalIcon(
                  onPressed: _archiveController.text.trim().isEmpty
                      ? null
                      : _copyArchive,
                  icon: const Icon(Icons.content_copy_outlined),
                  label: const Text('Copy archive'),
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Restore',
            subtitle:
                'Paste an archive below. Checksum validation runs before replacing local data.',
            child: Column(
              children: [
                TextField(
                  controller: _archiveController,
                  minLines: 5,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Paste archive JSON',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.restore_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.tonalIcon(
                        onPressed: _pickArchiveFile,
                        icon: const Icon(Icons.attach_file_outlined),
                        label: const Text('Pick archive file'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _restoreArchive,
                        icon: const Icon(Icons.verified_outlined),
                        label: const Text('Restore archive'),
                      ),
                    ),
                  ],
                ),
              ],
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

  void _generateArchive() {
    final archive = ref.read(ledgerProvider.notifier).exportArchive();
    setState(() {
      _archiveController.text = archive;
      _status = 'Archive generated (${archive.length} characters).';
    });
  }

  Future<void> _copyArchive() async {
    await Clipboard.setData(ClipboardData(text: _archiveController.text));
    if (!mounted) return;
    setState(() => _status = 'Archive copied to clipboard.');
    _showBackupMessage('Archive copied to clipboard.');
  }

  Future<void> _pickArchiveFile() async {
    try {
      final file = await pickTextFile(
        allowedExtensions: const ['json', 'txt', 'onewallet'],
      );
      if (file == null) {
        _showBackupMessage('Archive file selection cancelled.');
        return;
      }
      setState(() {
        _archiveController.text = file.text;
        _status = 'Loaded ${file.name}. Review and restore when ready.';
      });
      _showBackupMessage('Loaded ${file.name}.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'Archive file load failed: $error');
      _showBackupMessage('Archive file load failed.');
    }
  }

  Future<void> _restoreArchive() async {
    final archive = _archiveController.text.trim();
    if (archive.isEmpty) {
      _showBackupMessage('Paste an archive before restoring.');
      return;
    }
    try {
      await ref.read(ledgerProvider.notifier).importArchive(archive);
      if (!mounted) return;
      setState(() => _status = 'Archive restored successfully.');
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
