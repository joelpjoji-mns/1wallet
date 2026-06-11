import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/cloud_sync/rn_archive_compat.dart';
import 'package:one_wallet_flutter/src/data/ledger_codec.dart';

import 'fixtures/sample_ledger.dart';

void main() {
  test('decodes React Native archive ledger payload', () {
    final ledger =
        jsonDecode(encodeLedgerState(sampleLedgerState()))
            as Map<String, dynamic>;
    (ledger['accounts'] as List).first['color'] = '#16A34A';
    ledger['transactionSplits'] = const [];
    ledger['exchangeRates'] = [
      {
        'base': 'GBP',
        'quote': 'INR',
        'rate': 127.88,
        'asOfDate': '2026-06-09',
        'provider': 'frankfurter.app',
        'source': 'refresh',
      },
    ];
    ledger['merchants'] = const [];
    final checksum = reactNativeLedgerChecksum(jsonEncode(ledger));
    final archive = jsonEncode({
      'format': reactNativeArchiveFormat,
      'archiveVersion': reactNativeArchiveVersion,
      'ledgerStateVersion': currentLedgerStateVersion,
      'exportedAt': '2026-06-09T00:00:00.000Z',
      'source': 'mobile',
      'summary': {
        'accounts': (ledger['accounts'] as List).length,
        'categories': (ledger['categories'] as List).length,
        'transactions': (ledger['transactions'] as List).length,
        'transactionSplits': 0,
        'captureCandidates': (ledger['captureCandidates'] as List).length,
        'importBatches': (ledger['importBatches'] as List).length,
        'plannedPayments': 0,
        'loanAccounts': 0,
        'budgets': (ledger['budgets'] as List).length,
        'goals': (ledger['goals'] as List).length,
        'exchangeRates': 1,
        'currencies': ['INR'],
      },
      'ledger': ledger,
      'checksum': checksum,
    });

    final restored = decodeReactNativeOneWalletArchive(
      archive,
      userId: 'qa-user',
      expectedChecksum: checksum,
      expectedLedgerStateVersion: currentLedgerStateVersion,
    );

    expect(restored.userId, 'qa-user');
    expect(restored.accounts.length, sampleLedgerState().accounts.length);
    expect(restored.accounts.first.color?.toARGB32(), 0xFF16A34A);
    expect(restored.exchangeRates.single.base, 'GBP');
    expect(restored.exchangeRates.single.quote, 'INR');
    expect(restored.exchangeRates.single.rate, 127.88);
    expect(
      restored.transactions.length,
      sampleLedgerState().transactions.length,
    );
    expect(restored.preferences.baseCurrency, 'INR');
  });

  test('rejects checksum mismatch', () {
    final ledger =
        jsonDecode(encodeLedgerState(sampleLedgerState()))
            as Map<String, dynamic>;
    final archive = jsonEncode({
      'format': reactNativeArchiveFormat,
      'archiveVersion': reactNativeArchiveVersion,
      'ledgerStateVersion': currentLedgerStateVersion,
      'ledger': ledger,
      'checksum': 'fnv1a32:00000000',
    });

    expect(
      () => decodeReactNativeOneWalletArchive(archive, userId: 'qa-user'),
      throwsFormatException,
    );
  });

  test('checksum uses stable key order', () {
    expect(
      reactNativeLedgerChecksum(jsonEncode({
        'b': 2,
        'a': [
          {'z': true, 'm': null},
        ],
      })),
      reactNativeLedgerChecksum(jsonEncode({
        'a': [
          {'m': null, 'z': true},
        ],
        'b': 2,
      })),
    );
  });
}
