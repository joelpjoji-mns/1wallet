import 'dart:convert';

void main() {
  final json = '{"futureGenerationRules": [{"id": "1"}]}';
  final decoded = jsonDecode(json) as Map<String, dynamic>;
  final list = decoded['futureGenerationRules'] as List?;
  final filtered = list?.whereType<Map<String, dynamic>>().toList();
  print('Filtered: $filtered');
}
