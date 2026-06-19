import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('test shared prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('test_list', ['hello', 'world']);
    print(prefs.getStringList('test_list'));
  });
}
