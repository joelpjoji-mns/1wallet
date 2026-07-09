import 'package:flutter/material.dart';
import '../common/route_scaffold.dart';
import '../../imports/wallet_csv_parser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';

import '../../ledger/ledger_selectors.dart';
import '../../widgets/app_kit.dart';
import '../common/file_picker_utils.dart';

class ImportWalletCsvScreen extends ConsumerStatefulWidget {
  const ImportWalletCsvScreen({super.key});

  @override
  ConsumerState<ImportWalletCsvScreen> createState() =>
      _ImportWalletCsvScreenState();
}

class _ImportWalletCsvScreenState extends ConsumerState<ImportWalletCsvScreen> {
  final _csvController = TextEditingController();
  final _dateColumnController = TextEditingController(text: '1');
  final _accountColumnController = TextEditingController(text: '2');
  final _amountColumnController = TextEditingController(text: '3');
  final _categoryColumnController = TextEditingController(text: '4');
  final _notesColumnController = TextEditingController(text: '5');
  final _typeColumnController = TextEditingController(text: '6');
  final _currencyColumnController = TextEditingController(text: '7');
  ParsedWalletCsvResult? _preview;
  String? _status;
  var _manualMapping = false;
  var _mappingHasHeader = false;

  @override
  void dispose() {
    _csvController.dispose();
    _dateColumnController.dispose();
    _accountColumnController.dispose();
    _amountColumnController.dispose();
    _categoryColumnController.dispose();
    _notesColumnController.dispose();
    _typeColumnController.dispose();
    _currencyColumnController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final preview = _preview ?? _parseCsv(state);
    return RouteScaffold(
      title: 'Import Wallet CSV',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Paste CSV',
            subtitle:
                'Use columns like date, account, amount, category, notes, type, currency.',
            child: Column(
              children: [
                TextField(
                  controller: _csvController,
                  minLines: 7,
                  maxLines: 10,
                  onChanged: (_) => setState(() => _preview = null),
                  decoration: const InputDecoration(
                    labelText: 'CSV text',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.table_chart_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: _pickCsvFile,
                      icon: const Icon(Icons.attach_file_outlined),
                      label: const Text('Pick CSV file'),
                    ),
                    FilledButton.icon(
                      onPressed: _previewCsv,
                      icon: const Icon(Icons.preview_outlined),
                      label: const Text('Preview'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Column mapping',
            subtitle:
                'Override auto-detection when a CSV uses unusual column order.',
            child: Column(
              children: [
                LiquidGlassSwitchListTile(
                  value: _manualMapping,
                  onChanged: (value) => setState(() {
                    _manualMapping = value;
                    _preview = null;
                  }),
                  title: const Text('Manual column mapping'),
                  subtitle: const Text('Use 1-based column numbers'),
                ),
                if (_manualMapping) ...[
                  LiquidGlassSwitchListTile(
                    value: _mappingHasHeader,
                    onChanged: (value) => setState(() {
                      _mappingHasHeader = value;
                      _preview = null;
                    }),
                    title: const Text('First row is header'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      _ColumnNumberField(
                        label: 'Date column',
                        controller: _dateColumnController,
                        onChanged: _clearPreview,
                      ),
                      _ColumnNumberField(
                        label: 'Account column',
                        controller: _accountColumnController,
                        onChanged: _clearPreview,
                      ),
                      _ColumnNumberField(
                        label: 'Amount column',
                        controller: _amountColumnController,
                        onChanged: _clearPreview,
                      ),
                      _ColumnNumberField(
                        label: 'Category column',
                        controller: _categoryColumnController,
                        onChanged: _clearPreview,
                      ),
                      _ColumnNumberField(
                        label: 'Notes column',
                        controller: _notesColumnController,
                        onChanged: _clearPreview,
                      ),
                      _ColumnNumberField(
                        label: 'Type column',
                        controller: _typeColumnController,
                        onChanged: _clearPreview,
                      ),
                      _ColumnNumberField(
                        label: 'Currency column',
                        controller: _currencyColumnController,
                        onChanged: _clearPreview,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Preview',
            subtitle: '${preview.rows.length} importable rows',
            child: Column(
              children: [
                if (preview.rows.isEmpty)
                  const EmptyState(
                    icon: Icons.table_rows_outlined,
                    title: 'No rows ready',
                    body: 'Paste CSV text and preview importable rows.',
                  )
                else
                  for (final row in preview.rows.take(5)) ...[
                    PremiumRow(
                      icon: row.type == 'income'
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                      title: row.categoryName ?? transactionTypeLabel(row.type),
                      subtitle:
                          '${row.accountName.isEmpty ? 'Missing account name' : row.accountName} · row ${row.rowNumber}',
                      meta: formatMoney(row.amount, state.preferences.locale),
                      onTap: () =>
                          _showCsvMessage('CSV row ${row.rowNumber} is ready.'),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          FilledButton.icon(
            onPressed: preview.rows.isEmpty ? null : _importRows,
            icon: const Icon(Icons.playlist_add_check_outlined),
            label: const Text('Import rows'),
          ),
          if (_status != null) ...[
            const Gap(AppSpacing.lg),
            SectionCard(title: 'Status', child: Text(_status!)),
          ],
        ],
      ),
    );
  }

  Future<void> _pickCsvFile() async {
    try {
      final file = await pickTextFile(allowedExtensions: const ['csv', 'txt']);
      if (file == null) {
        _showCsvMessage('CSV file selection cancelled.');
        return;
      }
      final state = ref.read(ledgerProvider);
      setState(() {
        _csvController.text = file.text;
        _status = 'Loaded ${file.name} (${file.text.length} characters).';
        _preview = _parseCsv(state);
      });
      _showCsvMessage('Loaded ${file.name}.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'CSV file load failed: $error');
      _showCsvMessage('CSV file load failed.');
    }
  }

  void _previewCsv() {
    final state = ref.read(ledgerProvider);
    setState(() => _preview = _parseCsv(state));
  }

  Future<void> _importRows() async {
    final state = ref.read(ledgerProvider);
    final preview = _preview ?? _parseCsv(state);
    if (preview.rows.isEmpty) {
      _showCsvMessage('No CSV rows are ready to import.');
      return;
    }
    try {
      final count = await ref
          .read(ledgerProvider.notifier)
          .importWalletCsvRows(preview.rows);
      if (!mounted) return;
      setState(() {
        _preview = preview;
        final batches = ref.read(ledgerProvider).importBatches;
        final latestBatch = batches.isEmpty ? null : batches.first;
        _status = latestBatch == null
            ? '$count CSV rows imported as transactions.'
            : '${latestBatch.importedCount} imported, ${latestBatch.duplicateCount} duplicates skipped.';
      });
      _showCsvMessage('$count CSV rows imported.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'CSV import failed: $error');
      _showCsvMessage('CSV import failed.');
    }
  }

  void _showCsvMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }

  ParsedWalletCsvResult _parseCsv(LedgerState state) {
    return parseWalletCsv(
      _csvController.text,
      fallbackCurrency: state.preferences.baseCurrency,
      mapping: _manualMapping ? _mapping() : null,
    );
  }

  WalletCsvColumnMapping _mapping() {
    return WalletCsvColumnMapping(
      hasHeader: _mappingHasHeader,
      dateColumn: _columnNumber(_dateColumnController),
      accountColumn: _columnNumber(_accountColumnController),
      amountColumn: _columnNumber(_amountColumnController),
      categoryColumn: _columnNumber(_categoryColumnController),
      notesColumn: _columnNumber(_notesColumnController),
      typeColumn: _columnNumber(_typeColumnController),
      currencyColumn: _columnNumber(_currencyColumnController),
    );
  }

  int? _columnNumber(TextEditingController controller) {
    final parsed = int.tryParse(controller.text.trim());
    return parsed == null || parsed <= 0 ? null : parsed;
  }

  void _clearPreview(String _) {
    if (_preview != null) setState(() => _preview = null);
  }
}

class _ColumnNumberField extends StatelessWidget {
  const _ColumnNumberField({
    required this.label,
    required this.controller,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
