import 'dart:io';

void main() {
  final file = File('lib/src/features/transactions/transactions_screen.dart');
  var text = file.readAsStringSync();
  text = text.replaceAll(')\n    );', ');');
  file.writeAsStringSync(text);
}
