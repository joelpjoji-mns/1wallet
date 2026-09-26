import 'dart:io';

void main() {
  final file = File('lib/src/features/transactions/transactions_screen.dart');
  var lines = file.readAsLinesSync();
  
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].trim() == ')    )') {
      lines[i] = lines[i].replaceFirst(')    )', ');');
    }
    // Also there might be an extra `);`
    if (i >= 590 && i <= 600) {
      if (lines[i].trim() == ');' && lines[i-1].trim() == ')') {
        lines[i] = '';
      }
    }
  }

  // Let's print around line 590-600
  for (var i = 590; i < 600 && i < lines.length; i++) {
    print('\${i+1}: \${lines[i]}');
  }

  // Find the exact bug
  final text = file.readAsStringSync();
  final fixedText = text.replaceAll(')\n    )\n    );', ')\n    );');
  
  file.writeAsStringSync(fixedText);
}
