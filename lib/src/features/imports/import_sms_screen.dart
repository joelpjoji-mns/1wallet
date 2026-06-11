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
                InfoRow(
                  label: 'Warnings',
                  value: parsed.warnings.isEmpty
                      ? 'None'
                      : parsed.warnings.join(', '),
                  icon: Icons.warning_amber_outlined,
                  tone: parsed.warnings.isEmpty
                      ? MetricTone.standard
                      : MetricTone.warning,
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
      _showImportMessage('Error reading SMS: \$e');
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
