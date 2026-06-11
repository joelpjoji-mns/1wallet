import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:one_wallet_flutter/src/imports/picked_text_file.dart';

void main() {
  test('decodes valid picked text files', () {
    final file = decodePickedTextFile(
      name: 'wallet.csv',
      bytes: Uint8List.fromList('date,amount\n2026-06-08,10'.codeUnits),
      allowedExtensions: const ['csv'],
    );

    expect(file.name, 'wallet.csv');
    expect(file.text, contains('date,amount'));
  });

  test('rejects unsupported extensions', () {
    expect(
      () => decodePickedTextFile(
        name: 'wallet.pdf',
        bytes: Uint8List.fromList('data'.codeUnits),
        allowedExtensions: const ['csv'],
      ),
      throwsFormatException,
    );
  });

  test('rejects empty files', () {
    expect(
      () => decodePickedTextFile(
        name: 'wallet.csv',
        bytes: Uint8List(0),
        allowedExtensions: const ['csv'],
      ),
      throwsFormatException,
    );
  });

  test('rejects invalid utf8', () {
    expect(
      () => decodePickedTextFile(
        name: 'wallet.csv',
        bytes: Uint8List.fromList([0xff, 0xfe, 0xfd]),
        allowedExtensions: const ['csv'],
      ),
      throwsFormatException,
    );
  });
}
