import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../design/tokens.dart';
import '../../ledger/ledger_selectors.dart';
import '../../widgets/credit_card_view.dart';
import '../common/route_scaffold.dart';

class SecureAccountDetailsScreen extends ConsumerStatefulWidget {
  const SecureAccountDetailsScreen({super.key, required this.accountId});

  final String accountId;

  @override
  ConsumerState<SecureAccountDetailsScreen> createState() =>
      _SecureAccountDetailsScreenState();
}

class _SecureAccountDetailsScreenState
    extends ConsumerState<SecureAccountDetailsScreen> {
  // Card fields
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _ccvController = TextEditingController();

  // Bank fields
  final _accountNumberController = TextEditingController();

  // Custom fields
  final List<MapEntry<String, TextEditingController>> _customFields = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = ref.read(ledgerProvider);
      final account = state.accounts.firstWhere(
        (a) => a.id == widget.accountId,
      );

      print(
        'DEBUG: initState - Account type: ${account.type}, ID: ${account.id}',
      );
      print(
        'DEBUG: initState - encryptedDetails is ${account.encryptedDetails == null ? 'NULL' : 'NOT NULL, length: ${account.encryptedDetails!.length}'}',
      );

      if (account.encryptedDetails != null) {
        final key = encrypt.Key.fromUtf8('my32lengthsupersecretkey12345678');
        final iv = encrypt.IV(Uint8List(16));
        final encrypter = encrypt.Encrypter(encrypt.AES(key));

        try {
          final details = account.encryptedDetails!;
          print('DEBUG: details to decrypt = $details');
          details.forEach((k, v) {
            try {
              final decrypted = encrypter.decrypt64(v, iv: iv);
              print('DEBUG: Decrypted $k = $decrypted');
              if (k == 'number' || k == 'account_number') {
                if (account.type == 'card' || account.type == 'credit_card') {
                  _cardNumberController.text = decrypted;
                } else {
                  _accountNumberController.text = decrypted;
                }
              } else if (k == 'expiry') {
                _expiryController.text = decrypted;
              } else if (k == 'ccv') {
                _ccvController.text = decrypted;
              } else if (k == 'routing_number') {
                _customFields.add(
                  MapEntry(
                    'Routing Number',
                    TextEditingController(text: decrypted),
                  ),
                );
              } else if (k != 'name' && k != 'bank_name') {
                _customFields.add(
                  MapEntry(k, TextEditingController(text: decrypted)),
                );
              }
            } catch (e) {
              print('DEBUG: Decryption error on key $k with value $v: $e');
            }
          });
          if (mounted) {
            setState(() {});
          }
        } catch (e) {
          debugPrint('Decryption error: $e');
        }
      }
    });
  }

  void _copyToClipboard(String text) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text.replaceAll(RegExp(r'\s+'), '')));
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Copied to clipboard'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _addCustomField() async {
    final nameCtrl = TextEditingController();
    final valueCtrl = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Custom Field'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Field Name (e.g. PIN)',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: valueCtrl,
              decoration: const InputDecoration(labelText: 'Value'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result == true && nameCtrl.text.isNotEmpty && mounted) {
      setState(() {
        _customFields.add(MapEntry(nameCtrl.text, valueCtrl));
      });
    }
  }

  Future<void> _saveSecureDetails(Account account) async {
    final keyBytes = encrypt.Key.fromUtf8('my32lengthsupersecretkey12345678');
    final iv = encrypt.IV(Uint8List(16));
    final encrypter = encrypt.Encrypter(encrypt.AES(keyBytes));

    final Map<String, String> newEncrypted = {};
    final isCard = account.type == 'card' || account.type == 'credit_card';
    String? newCardLast4 = account.cardLast4;
    String? newAccountLast4 = account.accountLast4;

    if (isCard) {
      print(
        'DEBUG: Saving card details. Card Number is ${_cardNumberController.text.isNotEmpty ? 'NOT EMPTY' : 'EMPTY'}',
      );
      if (_cardNumberController.text.isNotEmpty)
        newEncrypted['number'] = encrypter
            .encrypt(_cardNumberController.text, iv: iv)
            .base64;
      if (_expiryController.text.isNotEmpty)
        newEncrypted['expiry'] = encrypter
            .encrypt(_expiryController.text, iv: iv)
            .base64;
      if (_ccvController.text.isNotEmpty)
        newEncrypted['ccv'] = encrypter
            .encrypt(_ccvController.text, iv: iv)
            .base64;

      if (_cardNumberController.text.length >= 4) {
        newCardLast4 = _cardNumberController.text.substring(
          _cardNumberController.text.length - 4,
        );
      }
    } else {
      print(
        'DEBUG: Saving bank details. Account Number is ${_accountNumberController.text.isNotEmpty ? 'NOT EMPTY' : 'EMPTY'}',
      );
      if (_accountNumberController.text.isNotEmpty)
        newEncrypted['account_number'] = encrypter
            .encrypt(_accountNumberController.text, iv: iv)
            .base64;

      if (_accountNumberController.text.length >= 4) {
        newAccountLast4 = _accountNumberController.text.substring(
          _accountNumberController.text.length - 4,
        );
      }
    }

    for (final field in _customFields) {
      if (field.value.text.isNotEmpty) {
        newEncrypted[field.key] = encrypter
            .encrypt(field.value.text, iv: iv)
            .base64;
      }
    }

    print(
      'DEBUG: newEncrypted map has ${newEncrypted.length} keys: $newEncrypted',
    );

    try {
      await ref
          .read(ledgerProvider.notifier)
          .upsertAccount(
            id: account.id,
            name: account.name,
            type: account.type,
            currency: account.currency,
            color: account.color,
            institution: account.institution,
            cardLast4: newCardLast4,
            accountLast4: newAccountLast4,
            includeInTotals: account.includeInTotals,
            includeInReports: account.includeInReports,
            includeInNetWorth: account.includeInNetWorth,
            showOnHome: account.showOnHome,
            isArchived: account.isArchived,
            encryptedDetails: newEncrypted.isNotEmpty ? newEncrypted : null,
          );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Secure details saved'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  Widget _buildFieldWithCopy(
    TextEditingController controller,
    String label, [
    TextInputType? type,
    int? maxLength,
    List<TextInputFormatter>? formatters,
  ]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: controller,
              decoration: InputDecoration(labelText: label),
              keyboardType: type ?? TextInputType.text,
              maxLength: maxLength,
              inputFormatters: formatters,
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: () => _copyToClipboard(controller.text),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final account = state.accounts.firstWhere((a) => a.id == widget.accountId);

    final isCard = account.type == 'card' || account.type == 'credit_card';
    final isCash = account.type == 'cash';

    return RouteScaffold(
      title: 'Secure Details',
      actions: [
        IconButton(
          icon: const Icon(Icons.check_rounded),
          onPressed: () => _saveSecureDetails(account),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isCard)
            CreditCardView(
              cardNumber: _cardNumberController.text,
              expiry: _expiryController.text,
              ccv: _ccvController.text,
              cardHolder: account.name,
              gradientStart:
                  account.color ?? Theme.of(context).colorScheme.primary,
              gradientEnd:
                  (account.color ?? Theme.of(context).colorScheme.primary)
                      .withAlpha(150),
              isUnlocked: true,
              customFields: Map.fromEntries(
                _customFields
                    .where((e) => e.value.text.isNotEmpty)
                    .map((e) => MapEntry(e.key, e.value.text)),
              ),
            )
          else
            CreditCardView(
              type: 'bank',
              cardNumber: _accountNumberController.text,
              expiry: '',
              ccv: '',
              cardHolder: account.name,
              gradientStart:
                  account.color ?? Theme.of(context).colorScheme.primary,
              gradientEnd:
                  (account.color ?? Theme.of(context).colorScheme.primary)
                      .withAlpha(150),
              isUnlocked: true,
              customFields: Map.fromEntries(
                _customFields
                    .where((e) => e.value.text.isNotEmpty)
                    .map((e) => MapEntry(e.key, e.value.text)),
              ),
            ),

          const SizedBox(height: AppSpacing.xxl),
          const Text(
            'Edit Details',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: AppSpacing.md),

          if (isCard) ...[
            _buildFieldWithCopy(
              _cardNumberController,
              'Card Number',
              TextInputType.number,
              19,
            ),
            Row(
              children: [
                Expanded(
                  child: _buildFieldWithCopy(
                    _expiryController,
                    'Expiry (MM/YY)',
                    TextInputType.number,
                    5,
                    [_ExpiryDateFormatter()],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildFieldWithCopy(
                    _ccvController,
                    'CVV',
                    TextInputType.number,
                    4,
                  ),
                ),
              ],
            ),
          ] else ...[
            _buildFieldWithCopy(
              _accountNumberController,
              'Account Number',
              TextInputType.number,
            ),
          ],

          const SizedBox(height: 24),

          if (_customFields.isNotEmpty) ...[
            const Divider(),
            const Text(
              'Custom Fields',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.md),
            for (var i = 0; i < _customFields.length; i++)
              Row(
                children: [
                  Expanded(
                    child: _buildFieldWithCopy(
                      _customFields[i].value,
                      _customFields[i].key,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    color: Theme.of(context).colorScheme.error,
                    onPressed: () {
                      setState(() {
                        _customFields.removeAt(i);
                      });
                    },
                  ),
                ],
              ),
          ],

          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _addCustomField,
            icon: const Icon(Icons.add),
            label: const Text('Add custom field'),
          ),

          const SizedBox(height: 24),
          const Text(
            'These details are encrypted and stored locally. The last 4 digits of your primary number will be mapped for SMS automation.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length < oldValue.text.length) {
      if (oldValue.text.length == 3 &&
          oldValue.text.endsWith('/') &&
          newValue.text.length == 2) {
        return TextEditingValue(
          text: newValue.text.substring(0, 1),
          selection: const TextSelection.collapsed(offset: 1),
        );
      }
      return newValue;
    }

    String newText = newValue.text.replaceAll('/', '');

    if (newText.length > 4) {
      newText = newText.substring(0, 4);
    }

    if (newText.length >= 3) {
      newText = '${newText.substring(0, 2)}/${newText.substring(2)}';
    } else if (newText.length == 2 &&
        newValue.text.length > oldValue.text.length) {
      newText = '$newText/';
    }

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}
