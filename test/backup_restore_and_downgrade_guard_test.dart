import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_wallet_flutter/src/cloud_sync/cloud_sync_write_guard.dart';
import 'package:one_wallet_flutter/src/data/ledger_defaults.dart';
import 'package:one_wallet_flutter/src/data/ledger_models.dart';
import 'package:one_wallet_flutter/src/imports/picked_text_file.dart';

TransactionRecord _createTx({
  required String id,
  required DateTime occurredAt,
  int amountMinor = 10000,
  String type = 'expense',
}) {
  return TransactionRecord(
    id: id,
    accountId: 'acc-1',
    amount: Money(amountMinor: amountMinor, currency: 'USD'),
    baseAmount: Money(amountMinor: amountMinor, currency: 'USD'),
    type: type,
    status: 'cleared',
    source: 'manual',
    occurredAt: occurredAt,
  );
}

void main() {
  group('Anti-downgrade safeguard in shouldPullCloudSnapshot', () {
    test('refuses to pull cloud snapshot when local transactions are newer', () {
      final now = DateTime.now();
      final localLatest = now;
      final cloudLatest = now.subtract(const Duration(days: 30)); // e.g. June 19th vs today

      final shouldPull = shouldPullCloudSnapshot(
        hasLocalUserData: true,
        hasUnsyncedLocalChanges: false,
        cloudUpdatedAt: now,
        localModifiedAt: now.subtract(const Duration(days: 1)),
        cloudRevision: 5,
        lastKnownCloudRevision: 2,
        cloudLastWriterDeviceId: 'other-device',
        localDeviceId: 'this-device',
        cloudLatestTransactionAt: cloudLatest,
        localLatestTransactionAt: localLatest,
      );

      expect(
        shouldPull,
        isFalse,
        reason: 'Cloud has older transactions than local; pulling would downgrade user data.',
      );
    });

    test('permits pull when cloud snapshot transactions are newer or equal', () {
      final now = DateTime.now();
      final localLatest = now.subtract(const Duration(days: 5));
      final cloudLatest = now;

      final shouldPull = shouldPullCloudSnapshot(
        hasLocalUserData: true,
        hasUnsyncedLocalChanges: false,
        cloudUpdatedAt: now,
        localModifiedAt: now.subtract(const Duration(days: 10)),
        cloudRevision: 5,
        lastKnownCloudRevision: 2,
        cloudLastWriterDeviceId: 'other-device',
        localDeviceId: 'this-device',
        cloudLatestTransactionAt: cloudLatest,
        localLatestTransactionAt: localLatest,
      );

      expect(shouldPull, isTrue);
    });

    test('permits pull when local ledger has no user data regardless of dates', () {
      final now = DateTime.now();
      final cloudLatest = now.subtract(const Duration(days: 100));

      final shouldPull = shouldPullCloudSnapshot(
        hasLocalUserData: false,
        hasUnsyncedLocalChanges: false,
        cloudUpdatedAt: now,
        localModifiedAt: null,
        cloudRevision: 1,
        lastKnownCloudRevision: null,
        cloudLastWriterDeviceId: 'other-device',
        localDeviceId: 'this-device',
        cloudLatestTransactionAt: cloudLatest,
        localLatestTransactionAt: null,
      );

      expect(
        shouldPull,
        isTrue,
        reason: 'Empty local ledger should pull existing cloud wallet.',
      );
    });
  });

  group('getLatestTransactionDate helper', () {
    test('returns null for empty transactions list', () {
      final ledger = emptyLedgerState();
      expect(getLatestTransactionDate(ledger), isNull);
    });

    test('returns latest date among transactions', () {
      final date1 = DateTime(2026, 6, 19);
      final date2 = DateTime(2026, 9, 29);
      final date3 = DateTime(2026, 8, 15);

      final ledger = emptyLedgerState().copyWith(
        transactions: [
          _createTx(id: 't1', occurredAt: date1),
          _createTx(id: 't2', occurredAt: date2),
          _createTx(id: 't3', occurredAt: date3),
        ],
      );

      expect(getLatestTransactionDate(ledger), equals(date2));
    });
  });

  group('LedgerState.isIncomingLedgerSafer', () {
    test('incoming ledger with newer records is safer', () {
      final olderDate = DateTime(2026, 6, 19);
      final newerDate = DateTime(2026, 9, 29);

      final current = emptyLedgerState().copyWith(
        transactions: [_createTx(id: 't1', occurredAt: olderDate)],
      );

      final incoming = emptyLedgerState().copyWith(
        transactions: [_createTx(id: 't2', occurredAt: newerDate)],
      );

      expect(LedgerState.isIncomingLedgerSafer(current, incoming), isTrue);
    });

    test('incoming ledger with more transactions is safer', () {
      final date = DateTime(2026, 9, 29);

      final current = emptyLedgerState().copyWith(
        transactions: [_createTx(id: 't1', occurredAt: date)],
      );

      final incoming = emptyLedgerState().copyWith(
        transactions: [
          _createTx(id: 't1', occurredAt: date),
          _createTx(id: 't2', occurredAt: date),
        ],
      );

      expect(LedgerState.isIncomingLedgerSafer(current, incoming), isTrue);
    });

    test('incoming ledger with fewer transactions and older date is NOT safer', () {
      final olderDate = DateTime(2026, 6, 19);
      final newerDate = DateTime(2026, 9, 29);

      final current = emptyLedgerState().copyWith(
        transactions: [
          _createTx(id: 't1', occurredAt: newerDate),
          _createTx(id: 't2', occurredAt: newerDate),
        ],
      );

      final incoming = emptyLedgerState().copyWith(
        transactions: [_createTx(id: 't0', occurredAt: olderDate)],
      );

      expect(LedgerState.isIncomingLedgerSafer(current, incoming), isFalse);
    });
  });

  group('decodePickedTextFile', () {
    test('decodes valid .onewallet json file', () {
      final jsonPayload = jsonEncode({
        'version': 1,
        'accounts': [],
        'transactions': [],
      });
      final bytes = Uint8List.fromList(utf8.encode(jsonPayload));

      final result = decodePickedTextFile(
        name: 'my_wallet.onewallet',
        bytes: bytes,
        allowedExtensions: const ['onewallet', 'json'],
      );

      expect(result.text, equals(jsonPayload));
      expect(result.name, equals('my_wallet.onewallet'));
    });

    test('decodes valid JSON even if file extension is missing or unexpected', () {
      final jsonPayload = jsonEncode({
        'version': 1,
        'accounts': [],
        'transactions': [],
      });
      final bytes = Uint8List.fromList(utf8.encode(jsonPayload));

      final result = decodePickedTextFile(
        name: 'backup_file_without_ext',
        bytes: bytes,
        allowedExtensions: const ['onewallet', 'json'],
      );

      expect(result.text, equals(jsonPayload));
    });

    test('rejects non-json content with unexpected extension', () {
      final bytes = Uint8List.fromList(utf8.encode('hello world raw text'));

      expect(
        () => decodePickedTextFile(
          name: 'some_image.png',
          bytes: bytes,
          allowedExtensions: const ['onewallet', 'json'],
        ),
        throwsFormatException,
      );
    });
  });
}
