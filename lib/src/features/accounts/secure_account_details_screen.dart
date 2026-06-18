import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../features/common/route_scaffold.dart';
import '../../widgets/credit_card_view.dart';

class SecureAccountDetailsScreen extends ConsumerStatefulWidget {
  final String accountId;

  const SecureAccountDetailsScreen({super.key, required this.accountId});

  @override
  ConsumerState<SecureAccountDetailsScreen> createState() => _SecureAccountDetailsScreenState();
}

class _SecureAccountDetailsScreenState extends ConsumerState<SecureAccountDetailsScreen> {
  final _auth = LocalAuthentication();
  bool _authenticated = false;
  final _nameController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _ccvController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final account = ref.read(ledgerProvider).accounts.firstWhere((a) => a.id == widget.accountId);
      _nameController.text = account.name;
    });
  }

  Future<void> _authenticate() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Authenticate to view/edit secure card details',
        biometricOnly: false,
      );
      setState(() => _authenticated = authenticated);
    } catch (e) {
      debugPrint('Auth error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ledgerProvider);
    final account = state.accounts.firstWhere((a) => a.id == widget.accountId);

    if (!_authenticated) {
      return RouteScaffold(
        title: 'Secure Details',
        child: Center(
          child: FilledButton.icon(
            onPressed: _authenticate,
            icon: const Icon(Icons.fingerprint),
            label: const Text('Unlock secure details'),
          ),
        ),
      );
    }

    return RouteScaffold(
      title: 'Secure Details',
      actions: [
        IconButton(
          icon: const Icon(Icons.check_rounded),
          onPressed: () => _saveSecureDetails(account),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CreditCardView(
            cardNumber: _cardNumberController.text.padRight(16, '*'),
            expiry: _expiryController.text.isEmpty ? 'MM/YY' : _expiryController.text,
            ccv: '***',
            cardHolder: _nameController.text,
            gradientStart: account.color ?? Theme.of(context).colorScheme.primary,
            gradientEnd: (account.color ?? Theme.of(context).colorScheme.primary).withAlpha(150),
          ),
          const SizedBox(height: 24),
          TextFormField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Card Holder Name'),
          ),
          TextFormField(
            controller: _cardNumberController,
            decoration: const InputDecoration(labelText: 'Card Number'),
            keyboardType: TextInputType.number,
            maxLength: 16,
          ),
          TextFormField(
            controller: _expiryController,
            decoration: const InputDecoration(labelText: 'Expiry (MM/YY)'),
          ),
          TextFormField(
            controller: _ccvController,
            decoration: const InputDecoration(labelText: 'CVV'),
            keyboardType: TextInputType.number,
            maxLength: 3,
          ),
        ],
      ),
    );
  }

  void _saveSecureDetails(Account account) async {
    // In production, use a secure key storage like flutter_secure_storage
    final key = encrypt.Key.fromUtf8('my32lengthsupersecretkey12345678'); 
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    final encrypted = {
      'number': encrypter.encrypt(_cardNumberController.text, iv: iv).base64,
      'expiry': encrypter.encrypt(_expiryController.text, iv: iv).base64,
      'ccv': encrypter.encrypt(_ccvController.text, iv: iv).base64,
      'name': encrypter.encrypt(_nameController.text, iv: iv).base64,
    };

    await ref.read(ledgerProvider.notifier).upsertAccount(
      id: account.id,
      name: _nameController.text,
      type: account.type,
      currency: account.currency,
      openingBalanceMinor: account.openingBalance.amountMinor,
      color: account.color,
      institution: account.institution,
      groupName: account.groupName,
      cardLast4: _cardNumberController.text.length >= 4 ? _cardNumberController.text.substring(_cardNumberController.text.length - 4) : account.cardLast4,
      encryptedDetails: encrypted,
    );
    
    if (mounted) context.pop();
  }
}
