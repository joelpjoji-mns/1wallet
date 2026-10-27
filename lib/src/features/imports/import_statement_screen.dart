import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
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

class _ImportStatementScreenState extends ConsumerState<ImportStatementScreen> {
  _ImportStep _step = _ImportStep.pick;
  bool _busy = false;
  String? _error;
  String? _fileName;

  // Parse results
  StatementParseResult? _result;
  String? _selectedAccountId;
  String? _selectedCurrency;
  bool _showRawText = false;

  // Raw text for re-parsing
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
              'Select any bank or credit card PDF statement. '
              'The smart self-recovering parser automatically extracts transactions, dates, amounts, and currency.',
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
                  'Reading and self-recovering statement…',
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
          title: 'Universal Statement Support',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFeatureRow(
                theme,
                Icons.check_circle_outline_rounded,
                'Multi-strategy engine adapts to any statement or card layout',
              ),
              const SizedBox(height: AppSpacing.xs),
              _buildFeatureRow(
                theme,
                Icons.currency_exchange_outlined,
                'Auto-detects currencies (₹ INR, \$ USD, € EUR, £ GBP, etc.)',
              ),
              const SizedBox(height: AppSpacing.xs),
              _buildFeatureRow(
                theme,
                Icons.lock_open_outlined,
                'Supports password-protected e-statements with smart password hints',
              ),
              const SizedBox(height: AppSpacing.xs),
              _buildFeatureRow(
                theme,
                Icons.auto_fix_high_outlined,
                'Self-recovers from wrapped lines, token headers, and card tables',
              ),
              const SizedBox(height: AppSpacing.xs),
              _buildFeatureRow(
                theme,
                Icons.security_outlined,
                '100% private & processed on-device (no financial data leaves your phone)',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureRow(ThemeData theme, IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.primary),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }

  // ── Step 2: Preview parsed rows ──

  Widget _buildPreviewStep(ThemeData theme) {
    final result = _result;
    if (result == null) return const SizedBox.shrink();
    final state = ref.watch(ledgerProvider);
    final accounts = state.accounts;

    final effectiveAccountId =
        _selectedAccountId ?? (accounts.isNotEmpty ? accounts.first.id : null);
    final effectiveCurrency = _selectedCurrency ?? result.detectedCurrency;

    const title = 'Account Statement';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary card
        SectionCard(
          title: title,
          subtitle: _fileName,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: MetricTile(
                      label: 'Parsed',
                      value: '${result.rows.length}',
                      icon: Icons.check_circle_outline_rounded,
                      compact: true,
                      tone: result.rows.isNotEmpty
                          ? MetricTone.positive
                          : MetricTone.warning,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: MetricTile(
                      label: 'Currency',
                      value: effectiveCurrency,
                      icon: Icons.payments_outlined,
                      compact: true,
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
              if (result.rows.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Icon(
                      Icons.auto_mode_outlined,
                      size: 14,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Parsed using ${result.strategy.label}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.7,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Target Account & Currency Configuration Card
        SectionCard(
          title: 'Import settings',
          child: Column(
            children: [
              if (accounts.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: effectiveAccountId,
                  decoration: const InputDecoration(
                    labelText: 'Target Account',
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
                        child: Text('${account.name} (${account.currency})'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _selectedAccountId = value);
                  },
                ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<String>(
                initialValue: effectiveCurrency,
                decoration: const InputDecoration(
                  labelText: 'Currency',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'INR', child: Text('INR (₹)')),
                  DropdownMenuItem(value: 'USD', child: Text('USD (\$)')),
                  DropdownMenuItem(value: 'EUR', child: Text('EUR (€)')),
                  DropdownMenuItem(value: 'GBP', child: Text('GBP (£)')),
                  DropdownMenuItem(value: 'CAD', child: Text('CAD (\$)')),
                  DropdownMenuItem(value: 'AUD', child: Text('AUD (\$)')),
                  DropdownMenuItem(value: 'SGD', child: Text('SGD (\$)')),
                  DropdownMenuItem(value: 'AED', child: Text('AED (د.إ)')),
                ],
                onChanged: (value) {
                  if (value == null || value == effectiveCurrency) return;
                  setState(() => _selectedCurrency = value);
                  _reParseWithCurrency(value, effectiveAccountId);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Transaction preview list or Diagnostic report
        SectionCard(
          title: 'Transactions preview',
          subtitle: '${result.rows.length} transactions found',
          child: result.rows.isEmpty
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    EmptyState(
                      icon: Icons.search_off_outlined,
                      title: 'No transactions found',
                      body:
                          result.diagnostics ??
                          'The statement text could not be parsed into transactions.',
                    ),
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _reParseRelaxed(
                              effectiveCurrency,
                              effectiveAccountId,
                            ),
                      icon: const Icon(Icons.refresh_outlined),
                      label: const Text('Try Relaxed Scanner Mode'),
                    ),
                  ],
                )
              : Column(
                  children: [
                    for (var i = 0; i < result.rows.length && i < 50; i++) ...[
                      _TransactionPreviewTile(
                        row: result.rows[i],
                        currency: effectiveCurrency,
                      ),
                      if (i < result.rows.length - 1 && i < 49)
                        const Divider(height: 1),
                    ],
                    if (result.rows.length > 50)
                      Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.sm),
                        child: Text(
                          '… and ${result.rows.length - 50} more',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),

        const SizedBox(height: AppSpacing.md),

        // Optional Raw Text Debug Viewer
        if (_rawText != null)
          OutlinedButton.icon(
            onPressed: () => setState(() => _showRawText = !_showRawText),
            icon: Icon(
              _showRawText
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
            ),
            label: Text(
              _showRawText ? 'Hide extracted text' : 'View extracted PDF text',
            ),
          ),

        if (_showRawText && _rawText != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            height: 200,
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: AppSurfaces.panel(context),
            child: SingleChildScrollView(
              child: SelectableText(
                _rawText!,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
              ),
            ),
          ),
        ],

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
                        _selectedCurrency = null;
                        _showRawText = false;
                      }),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy || result.rows.isEmpty
                    ? null
                    : () =>
                          _confirmImport(effectiveAccountId, effectiveCurrency),
                icon: const Icon(Icons.file_download_done_outlined),
                label: Text('Import ${result.rows.length}'),
              ),
            ),
          ],
        ),

        if (_error != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
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
            Icons.check_circle_outline_rounded,
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
            'You can undo this import from the Data & Sync screen by rolling back the import batch.',
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
                    _selectedCurrency = null;
                    _showRawText = false;
                  }),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Import another'),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.done_rounded),
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

      // Extract text from PDF, prompting for password if protected.
      String rawText = '';
      String? password;
      var unlocked = false;

      while (!unlocked) {
        try {
          rawText = await compute(_runPdfExtractor, (
            bytes: bytes,
            password: password,
          ));
          unlocked = true;
        } catch (e) {
          final errStr = e.toString().toLowerCase();
          if (errStr.contains('password') || errStr.contains('encrypted')) {
            if (!mounted) return;
            final enteredPassword = await _showPasswordDialog(
              isRetry: password != null,
            );
            if (enteredPassword == null || enteredPassword.isEmpty) {
              setState(() => _busy = false);
              return;
            }
            password = enteredPassword;
          } else {
            rethrow;
          }
        }
      }

      if (rawText.trim().isEmpty) {
        throw Exception(
          'No readable text found in this PDF. '
          'Scanned image-based PDFs without selectable text are not supported.',
        );
      }

      final state = ref.read(ledgerProvider);
      final accounts = state.accounts;
      final accountName = accounts.isNotEmpty ? accounts.first.name : '';

      final parseResult = await compute(_runStatementParser, (
        fullText: rawText,
        accountName: accountName,
        currency: null,
        forceRelaxed: false,
      ));

      setState(() {
        _busy = false;
        _step = _ImportStep.preview;
        _rawText = rawText;
        _fileName = file.name;
        _result = parseResult;
        _selectedCurrency = parseResult.detectedCurrency;
      });
    } catch (e) {
      setState(() {
        _busy = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<String?> _showPasswordDialog({bool isRetry = false}) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(isRetry ? 'Incorrect password' : 'PDF password required'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isRetry
                  ? 'The password was incorrect. Please try again:'
                  : 'This statement is password-protected. Enter the password to unlock:',
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: controller,
              autofocus: true,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (val) => Navigator.of(ctx).pop(val),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Text(
                '💡 Common PDF statement password formats:\n'
                '• Date of Birth (DDMMYYYY or DDMM)\n'
                '• Customer ID, PAN number, or Account number\n'
                '• First 4 letters of your name + last 4 digits of phone/account\n'
                '• Lowercase name + birth year (YYYY)',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Unlock'),
          ),
        ],
      ),
    );
  }

  Future<void> _reParseWithCurrency(String currency, String? accountId) async {
    if (_rawText == null) return;
    final state = ref.read(ledgerProvider);
    final accountName = _getAccountName(state.accounts, accountId ?? '');

    final reResult = await compute(_runStatementParser, (
      fullText: _rawText!,
      accountName: accountName,
      currency: currency,
      forceRelaxed: false,
    ));

    if (!mounted) return;
    setState(() {
      _result = reResult;
    });
  }

  Future<void> _reParseRelaxed(String currency, String? accountId) async {
    if (_rawText == null) return;
    setState(() => _busy = true);

    final state = ref.read(ledgerProvider);
    final accountName = _getAccountName(state.accounts, accountId ?? '');

    final reResult = await compute(_runStatementParser, (
      fullText: _rawText!,
      accountName: accountName,
      currency: currency,
      forceRelaxed: true,
    ));

    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = reResult;
    });
  }

  Future<void> _confirmImport(String? accountId, String currency) async {
    final result = _result;
    if (result == null || result.rows.isEmpty) return;

    final state = ref.read(ledgerProvider);
    if (state.accounts.isEmpty) {
      setState(() => _error = 'Create an account before importing.');
      return;
    }

    final effectiveAccountId = accountId ?? state.accounts.first.id;
    final accountName = _getAccountName(state.accounts, effectiveAccountId);

    final rows = result.rows
        .map(
          (row) => ParsedWalletCsvRow(
            rowNumber: row.rowNumber,
            accountName: accountName,
            amount: Money(
              amountMinor: row.amount.amountMinor,
              currency: currency,
            ),
            type: row.type,
            categoryName: row.categoryName,
            notes: row.notes,
            occurredAt: row.occurredAt,
          ),
        )
        .toList();

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final imported = await ref
          .read(ledgerProvider.notifier)
          .importWalletCsvRows(rows);

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
  const _TransactionPreviewTile({required this.row, required this.currency});

  final ParsedWalletCsvRow row;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpense = row.type == 'expense';
    final sign = isExpense ? '-' : '+';
    final color = isExpense
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    final amountStr = _formatAmount(row.amount.amountMinor, currency);
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

  String _formatAmount(int minor, String curr) {
    final major = minor / 100;
    final formatter = NumberFormat.currency(
      symbol: _currencySymbol(curr),
      decimalDigits: 2,
    );
    return formatter.format(major);
  }

  String _currencySymbol(String curr) {
    switch (curr.toUpperCase()) {
      case 'INR':
        return '₹';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'AED':
        return 'د.إ';
      default:
        return '$curr ';
    }
  }
}

String _runPdfExtractor(({Uint8List bytes, String? password}) args) {
  return extractAllTextFromPdf(args.bytes, password: args.password);
}

StatementParseResult _runStatementParser(
  ({String fullText, String accountName, String? currency, bool? forceRelaxed})
  args,
) {
  return parseStatement(
    args.fullText,
    accountName: args.accountName,
    defaultCurrency: args.currency,
    forceRelaxedMode: args.forceRelaxed ?? false,
  );
}
