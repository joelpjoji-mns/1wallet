import 'package:flutter_test/flutter_test.dart';
import 'package:encrypt/encrypt.dart';

void main() {
  test('Encryption padding test', () {
    final key = Key.fromUtf8('my32lengthsupersecretkey12345678');
    final iv = IV.fromLength(16);
    final encrypter = Encrypter(AES(key));

    final text = '1234567890';
    final encrypted = encrypter.encrypt(text, iv: iv).base64;
    print('Encrypted: $encrypted');

    final decrypted = encrypter.decrypt64(encrypted, iv: iv);
    print('Decrypted: $decrypted');
    
    expect(decrypted, text);
  });
}
