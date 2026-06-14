import 'package:flutter/material.dart';
import '../common/route_scaffold.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../capture/message_parser.dart';
import '../capture/sms_inbox_reader.dart';

import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';

import '../../widgets/app_kit.dart';

class ImportSmsScreen extends ConsumerStatefulWidget {
  const ImportSmsScreen({super.key, this.title = 'Import SMS'});

  final String title;

  @override
  ConsumerState<ImportSmsScreen> createState() => _ImportSmsScreenState();
}

class _ImportSmsScreenState extends ConsumerState<ImportSmsScreen> {
  final _messageController = TextEditingController();
  ParsedTransactionMessage? _preview;
  String _scanTimeframe = '24h';
  bool _isScanning = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final parsed =
        _preview ??
        parseTransactionMessage(
          _messageController.text,
          fallbackCurrency: state.preferences.baseCurrency,
        );
    return RouteScaffold(
      title: widget.title,
      actions: [
        HeaderIconButton(icon: Icons.inbox_outlined, onPressed: _scanInbox),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCard(
            title: 'Batch scan SMS',
            subtitle: 'Automatically find and queue transactions from your inbox.',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: _scanTimeframe,
                  decoration: const InputDecoration(
                    labelText: 'Scan timeframe',
                    prefixIcon: Icon(Icons.history_rounded),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'today', child: Text('Today (since midnight)')),
                    DropdownMenuItem(value: '24h', child: Text('Last 24 hours')),
                    DropdownMenuItem(value: '7d', child: Text('Last 7 days')),
                    DropdownMenuItem(value: '30d', child: Text('Last 30 days')),
                  ],
                  onChanged: _isScanning ? null : (value) {
                    if (value != null) setState(() => _scanTimeframe = value);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(
                  onPressed: _isScanning ? null : _startBatchScan,
                  icon: _isScanning 
                      ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary)) 
                      : const Icon(Icons.manage_search_rounded),
                  label: Text(_isScanning ? 'Scanning...' : 'Start scan'),
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Paste message',
            subtitle: 'Local parser extracts amount, merchant, and direction.',
            child: Column(
              children: [
                TextField(
                  controller: _messageController,
                  minLines: 5,
                  maxLines: 8,
                  onChanged: (_) => setState(() => _preview = null),
                  decoration: const InputDecoration(
                    labelText: 'SMS or notification text',
                    alignLabelWithHint: true,
                    prefixIcon: Icon(Icons.sms_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilledButton.icon(
                    onPressed: _parsePreview,
                    icon: const Icon(Icons.auto_fix_high_outlined),
                    label: const Text('Parse message'),
                  ),
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          SectionCard(
            title: 'Parser preview',
            subtitle: parsed.ignored
                ? 'This message will not be queued.'
                : 'Review this candidate before adding it to the queue.',
            child: Column(
              children: [
                InfoRow(
                  label: 'Outcome',
                  value: parsed.ignored ? 'Ignored' : 'Review candidate',
                  icon: parsed.ignored
                      ? Icons.visibility_off_outlined
                      : Icons.fact_check_outlined,
                  tone: parsed.ignored
                      ? MetricTone.warning
                      : MetricTone.standard,
                ),
                InfoRow(
                  label: 'Type',
                  value: parsed.transactionType == null
                      ? 'Needs review'
                      : transactionTypeLabel(parsed.transactionType!),
                  icon: Icons.swap_vert_rounded,
                ),
                InfoRow(
                  label: 'Amount',
                  value: parsed.amount == null
                      ? 'Not detected'
                      : formatMoney(parsed.amount!, state.preferences.locale),
                  icon: Icons.payments_outlined,
                ),
                InfoRow(
                  label: 'Merchant',
                  value: parsed.merchant ?? 'Not detected',
                  icon: Icons.storefront_outlined,
                ),
              ],
            ),
          ),
          const Gap(AppSpacing.lg),
          FilledButton.icon(
            onPressed: parsed.ignored ? null : _queueCandidate,
            icon: const Icon(Icons.playlist_add_check_outlined),
            label: const Text('Add to review queue'),
          ),
        ],
      ),
    );
  }

  Future<void> _scanInbox() async {
    final status = await requestAndroidSmsPermission();
    if (status != AndroidSmsPermissionStatus.granted) {
      _showImportMessage('Permission denied to read SMS inbox.');
      return;
    }

    _showImportMessage('Scanning inbox...');
    try {
      final messages = await readAndroidSmsInbox(maxCount: 20);
      if (messages.isEmpty) {
        _showImportMessage('No recent SMS found.');
        return;
      }

      // Paste the first valid one
      setState(() {
        _messageController.text = messages.first.body;
      });
      _parsePreview();
      _showImportMessage('Loaded latest SMS from inbox.');
    } catch (e) {
      _showImportMessage('Error reading SMS: $e');
    }
  }

  Future<void> _startBatchScan() async {
    final status = await requestAndroidSmsPermission();
    if (status != AndroidSmsPermissionStatus.granted) {
      _showImportMessage('Permission denied to read SMS inbox.');
      return;
    }

    setState(() => _isScanning = true);
    
    try {
      final now = DateTime.now();
      DateTime minDate;
      switch (_scanTimeframe) {
        case 'today':
          minDate = DateTime(now.year, now.month, now.day);
          break;
        case '7d':
          minDate = now.subtract(const Duration(days: 7));
          break;
        case '30d':
          minDate = now.subtract(const Duration(days: 30));
          break;
        case '24h':
        default:
          minDate = now.subtract(const Duration(hours: 24));
          break;
      }
      
      final minDateMs = minDate.millisecondsSinceEpoch;
      
      final messages = await readAndroidSmsInbox(maxCount: 500, minDate: minDateMs);
      if (messages.isEmpty) {
        _showImportMessage('No messages found in the selected timeframe.');
        return;
      }

      int found = 0;
      final state = ref.read(ledgerProvider);
      final fallbackCurrency = state.preferences.baseCurrency;
      final notifier = ref.read(ledgerProvider.notifier);
      final validTexts = <String>[];
      
      for (final msg in messages) {
        final parsed = parseTransactionMessage(msg.body, fallbackCurrency: fallbackCurrency);
        if (!parsed.ignored && parsed.transactionType != null) {
          validTexts.add(msg.body);
          found++;
        }
      }
      
      final candidates = await notifier.importSmsMessagesBatch(validTexts);
      
      _showImportMessage('Scan complete. Found $found candidates, queued ${candidates.length}.');
    } catch (e) {
      _showImportMessage('Error scanning SMS: $e');
    } finally {
      if (mounted) {
        setState(() => _isScanning = false);
      }
    }
  }

  void _parsePreview() {
    final state = ref.read(ledgerProvider);
    setState(() {
      _preview = parseTransactionMessage(
        _messageController.text,
        fallbackCurrency: state.preferences.baseCurrency,
      );
    });
  }

  Future<void> _queueCandidate() async {
    final candidate = await ref
        .read(ledgerProvider.notifier)
        .importSmsMessage(_messageController.text);
    if (!mounted) return;
    if (candidate == null) {
      _showImportMessage('Message ignored. Nothing was added.');
      return;
    }
    setState(() {
      _preview = parseTransactionMessage(
        _messageController.text,
        fallbackCurrency: ref.read(ledgerProvider).preferences.baseCurrency,
      );
    });
    _showImportMessage('SMS candidate added to review.');
  }

  void _showImportMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
  }
}
