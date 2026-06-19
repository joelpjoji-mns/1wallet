import 'package:encrypt/encrypt.dart';

void main() {
  final key = Key.fromUtf8('my32lengthsupersecretkey12345678');
  final iv = IV.fromLength(16);
  final encrypter = Encrypter(AES(key));

  final encrypted = 't/wzyUFdaf68rvkQi4GpcQ==';
  
  try {
    final decrypted = encrypter.decrypt64(encrypted, iv: iv);
    print('Decrypted: $decrypted');
  } catch (e) {
    print('Decryption error: $e');
  }
}
