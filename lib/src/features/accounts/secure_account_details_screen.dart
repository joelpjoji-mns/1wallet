import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

import '../../data/ledger_models.dart';
import '../../data/ledger_providers.dart';
import '../../features/common/route_scaffold.dart';

class SecureAccountDetailsScreen extends ConsumerStatefulWidget {
  final String accountId;

  const SecureAccountDetailsScreen({super.key, required this.accountId});

  @override
  ConsumerState<SecureAccountDetailsScreen> createState() => _SecureAccountDetailsScreenState();
}

class _SecureAccountDetailsScreenState extends ConsumerState<SecureAccountDetailsScreen> {
  final _auth = LocalAuthentication();
  bool _authenticated = false;
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _ccvController = TextEditingController();

  Future<void> _authenticate() async {
    try {
      final authenticated = await _auth.authenticate(
        localizedReason: 'Authenticate to view secure card details',
        options: AuthenticationOptions(biometricOnly: false),
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
          TextFormField(
            controller: _cardNumberController,
            decoration: const InputDecoration(labelText: 'Card Number'),
            keyboardType: TextInputType.number,
          ),
          TextFormField(
            controller: _expiryController,
            decoration: const InputDecoration(labelText: 'Expiry (MM/YY)'),
          ),
          TextFormField(
            controller: _ccvController,
            decoration: const InputDecoration(labelText: 'CVV'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
    );
  }

  void _saveSecureDetails(Account account) async {
    final key = encrypt.Key.fromLength(32);
    final iv = encrypt.IV.fromLength(16);
    final encrypter = encrypt.Encrypter(encrypt.AES(key));

    final encrypted = {
      'number': encrypter.encrypt(_cardNumberController.text, iv: iv).base64,
      'expiry': encrypter.encrypt(_expiryController.text, iv: iv).base64,
      'ccv': encrypter.encrypt(_ccvController.text, iv: iv).base64,
    };

    await ref.read(ledgerProvider.notifier).upsertAccount(
      id: account.id,
      name: account.name,
      type: account.type,
      currency: account.currency,
      openingBalance: account.openingBalance,
      encryptedDetails: encrypted,
    );
    
    if (mounted) context.pop();
  }
}
