import 'dart:convert';

void main() {
  const json = '{"futureGenerationRules": [{"id": "1"}]}';
  final decoded = jsonDecode(json) as Map<String, dynamic>;
  final list = decoded['futureGenerationRules'] as List?;
  final filtered = list?.whereType<Map<String, dynamic>>().toList();
  // ignore: avoid_print
  print('Filtered: $filtered');
}
