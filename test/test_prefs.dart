import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Test SharedPreferences List encoding', () {
    SharedPreferences.setMockInitialValues({
      'flutter.test_key': ['a', 'b']
    });
    
    // We cannot easily test the raw Android XML via mock, but we can verify it works.
  });
}
