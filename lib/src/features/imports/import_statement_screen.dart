import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../imports/bank_profiles.dart';
import '../../imports/pdf_text_extractor.dart';
import '../../imports/statement_parser.dart';
import '../../imports/wallet_csv_parser.dart' show ParsedWalletCsvRow;
import '../../widgets/app_kit.dart';
import '../common/route_scaffold.dart';

class ImportStatementScreen extends ConsumerStatefulWidget {
  const ImportStatementScreen({super.key});

  @override
  ConsumerState<ImportStatementScreen> createState() =>
      _ImportStatementScreenState();
}

enum _ImportStep { pick, preview, done }

class _ImportStatementScreenState
    extends ConsumerState<ImportStatementScreen> {
  _ImportStep _step = _ImportStep.pick;
  bool _busy = false;
  String? _error;
  String? _fileName;

  // Parse results
  StatementParseResult? _result;
  BankProfile? _selectedProfile;
  String? _selectedAccountId;

  // Raw text for re-parsing with different profile
  String? _rawText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RouteScaffold(
      title: 'Import statement',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_step == _ImportStep.pick) _buildPickStep(theme),
          if (_step == _ImportStep.preview) _buildPreviewStep(theme),
          if (_step == _ImportStep.done) _buildDoneStep(theme),
        ],
      ),
    );
  }

  // ── Step 1: Pick PDF ──

  Widget _buildPickStep(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          title: 'Import from PDF',
          subtitle:
              'Pick a bank statement PDF to extract transactions. '
              'Supports SBI, HDFC, ICICI, Axis, Kotak, PNB, and other Indian banks.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _pickPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Select PDF statement'),
              ),
              if (_busy) ...[
                const SizedBox(height: AppSpacing.md),
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Extracting text from PDF…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          SectionCard(
            title: 'Error',
            child: Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        SectionCard(
          title: 'Supported banks',
          child: Column(
            children: [
              for (final profile in allBankProfiles
                  .where((p) => p.id != 'generic_in'))
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(
                        Icons.account_balance_outlined,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(profile.name, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  'Other banks with standard statement formats may also work.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Step 2: Preview parsed rows ──

  Widget _buildPreviewStep(ThemeData theme) {
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    final state = ref.watch(ledgerProvider);
    final accounts = state.accounts;

    // Default to first account if none selected.
    final effectiveAccountId =
        _selectedAccountId ?? (accounts.isNotEmpty ? accounts.first.id : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary card
        SectionCard(
          title: 'Detected: ${result.profile.name}',
          subtitle: _fileName,
          child: Row(
            children: [
              Expanded(
                child: MetricTile(
                  label: 'Parsed',
                  value: '${result.rows.length}',
                  icon: Icons.check_circle_outline,
                  compact: true,
                  tone: result.rows.isNotEmpty
                      ? MetricTone.positive
                      : MetricTone.warning,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: MetricTile(
                  label: 'Skipped',
                  value: '${result.skippedLines}',
                  icon: Icons.skip_next_outlined,
                  compact: true,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Bank profile override
        SectionCard(
          title: 'Bank profile',
          child: DropdownButtonFormField<String>(
            value: _selectedProfile?.id ?? result.profile.id,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
            ),
            items: [
              for (final profile in allBankProfiles)
                DropdownMenuItem(
                  value: profile.id,
                  child: Text(profile.name),
                ),
            ],
            onChanged: (value) {
              if (value == null || _rawText == null) return;
              final newProfile = allBankProfiles.firstWhere(
                (p) => p.id == value,
              );
              setState(() {
                _selectedProfile = newProfile;
                _result = parseStatement(
                  _rawText!,
                  profile: newProfile,
                  accountName:
                      _getAccountName(accounts, effectiveAccountId ?? ''),
                );
              });
            },
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Target account selector
        if (accounts.isNotEmpty)
          SectionCard(
            title: 'Import to account',
            child: DropdownButtonFormField<String>(
              value: effectiveAccountId,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
              ),
              items: [
                for (final account in accounts)
                  DropdownMenuItem(
                    value: account.id,
                    child: Text(account.name),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _selectedAccountId = value);
              },
            ),
          ),

        const SizedBox(height: AppSpacing.md),

        // Transaction preview list
        SectionCard(
          title: 'Transactions preview',
          subtitle: '${result.rows.length} transactions found',
          child: result.rows.isEmpty
              ? EmptyState(
                  icon: Icons.search_off_outlined,
                  title: 'No transactions found',
                  body:
                      'Try selecting a different bank profile, or the statement format may not be supported yet.',
                )
              : Column(
                  children: [
                    for (var i = 0;
                        i < result.rows.length && i < 50;
                        i++) ...[
                      _TransactionPreviewTile(row: result.rows[i]),
                      if (i < result.rows.length - 1 && i < 49)
                        const Divider(height: 1),
                    ],
                    if (result.rows.length > 50)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(
                          '… and ${result.rows.length - 50} more',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                  ],
                ),
        ),

        const SizedBox(height: AppSpacing.lg),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _step = _ImportStep.pick;
                          _result = null;
                          _rawText = null;
                          _error = null;
                          _fileName = null;
                          _selectedProfile = null;
                        }),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy || result.rows.isEmpty
                    ? null
                    : () => _confirmImport(effectiveAccountId),
                icon: const Icon(Icons.file_download_done_outlined),
                label: Text('Import ${result.rows.length}'),
              ),
            ),
          ],
        ),

        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(
            _error!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
      ],
    );
  }

  // ── Step 3: Done ──

  Widget _buildDoneStep(ThemeData theme) {
    return SectionCard(
      title: 'Import complete',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Transactions imported successfully from $_fileName.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'You can undo this import from the Sync screen by rolling back the import batch.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _step = _ImportStep.pick;
                    _result = null;
                    _rawText = null;
                    _error = null;
                    _fileName = null;
                    _selectedProfile = null;
                  }),
                  icon: const Icon(Icons.add),
                  label: const Text('Import another'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.done),
                  label: const Text('Done'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Actions ──

  Future<void> _pickPdf() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (files.isEmpty) {
        setState(() => _busy = false);
        return;
      }

      final file = files.single;
      Uint8List bytes;
      try {
        bytes = await file.readAsBytes();
      } catch (_) {
        if (file.path != null) {
          bytes = await File(file.path!).readAsBytes();
        } else {
          throw Exception('Could not read the selected file.');
        }
      }

      if (bytes.isEmpty) {
        throw Exception('The selected PDF file is empty.');
      }

      // Extract text from PDF.
      final rawText = extractAllTextFromPdf(bytes);
      if (rawText.trim().isEmpty) {
        throw Exception(
          'No readable text found in this PDF. '
          'Scanned/image-based PDFs are not currently supported.',
        );
      }

      // Parse with auto-detected profile.
      final state = ref.read(ledgerProvider);
      final accounts = state.accounts;
      final accountName = accounts.isNotEmpty ? accounts.first.name : '';

      final parseResult = parseStatement(
        rawText,
        accountName: accountName,
      );

      setState(() {
        _busy = false;
        _step = _ImportStep.preview;
        _rawText = rawText;
        _fileName = file.name;
        _result = parseResult;
        _selectedProfile = parseResult.profile;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _confirmImport(String? accountId) async {
    final result = _result;
    if (result == null || result.rows.isEmpty) return;

    final state = ref.read(ledgerProvider);
    if (state.accounts.isEmpty) {
      setState(() => _error = 'Create an account before importing.');
      return;
    }

    final effectiveAccountId = accountId ?? state.accounts.first.id;
    final accountName = _getAccountName(state.accounts, effectiveAccountId);

    // Re-map rows with the selected account name.
    final rows = result.rows
        .map((row) => ParsedWalletCsvRow(
              rowNumber: row.rowNumber,
              accountName: accountName,
              amount: row.amount,
              type: row.type,
              categoryName: row.categoryName,
              notes: row.notes,
              occurredAt: row.occurredAt,
            ))
        .toList();

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final imported =
          await ref.read(ledgerProvider.notifier).importWalletCsvRows(rows);

      if (!mounted) return;
      setState(() {
        _busy = false;
        _step = _ImportStep.done;
      });
      _showMessage('Imported $imported transactions from $_fileName.');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Import failed: $e';
      });
    }
  }

  String _getAccountName(List<Account> accounts, String accountId) {
    for (final account in accounts) {
      if (account.id == accountId) return account.name;
    }
    return accounts.isNotEmpty ? accounts.first.name : '';
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}

// ── Preview Row Widget ──

class _TransactionPreviewTile extends StatelessWidget {
  const _TransactionPreviewTile({required this.row});

  final ParsedWalletCsvRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpense = row.type == 'expense';
    final sign = isExpense ? '-' : '+';
    final color = isExpense
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    final amountStr = _formatAmount(row.amount);
    final dateStr = row.occurredAt != null
        ? DateFormat('dd MMM yyyy').format(row.occurredAt!)
        : '—';

    return Padding(
      padding: const EdgeInsets.symmetric(
        vertical: AppSpacing.sm,
        horizontal: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Icon(
            isExpense
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.notes ?? 'Row ${row.rowNumber}',
                  style: theme.textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  dateStr,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          Text(
            '$sign$amountStr',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _formatAmount(Money amount) {
    final major = amount.amountMinor / 100;
    final formatter = NumberFormat.currency(
      symbol: _currencySymbol(amount.currency),
      decimalDigits: 2,
    );
    return formatter.format(major);
  }

  String _currencySymbol(String currency) {
    switch (currency.toUpperCase()) {
      case 'INR':
        return '₹';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return currency;
    }
  }
}
