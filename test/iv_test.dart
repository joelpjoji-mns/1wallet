import 'package:flutter_test/flutter_test.dart';
import 'package:encrypt/encrypt.dart';

void main() {
  test('IV randomness test', () {
    final iv1 = IV.fromLength(16);
    final iv2 = IV.fromLength(16);
    
    print('IV1: ${iv1.base64}');
    print('IV2: ${iv2.base64}');
  });
}
