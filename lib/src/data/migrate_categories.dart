import 'dart:convert';
import 'dart:io';
import 'category_taxonomy.dart';

String fnv1a32Hex(String source) {
  const offsetBasis = 0x811c9dc5;
  const prime = 0x01000193;
  var hash = offsetBasis;
  for (final byte in utf8.encode(source)) {
    hash ^= byte;
    hash = (hash * prime) & 0xffffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

void main() {
  final file = File('../../../1wallet_backup_fixed.onewallet');
  final contents = file.readAsStringSync();
  final decoded = jsonDecode(contents) as Map<String, dynamic>;
  final payloadStr = decoded['payload'] as String;
  final payload = jsonDecode(payloadStr) as Map<String, dynamic>;

  // Mapping from old legacy categories to new taxonomy
  final Map<String, String> catMap = {
    '0b627330-994d-45ba-a7b9-467f3047e372': 'cat-dining',
    'cat-transport': 'cat-transit',
    '2806dd37-28e9-4a1d-9c71-b76c76f29df5': 'cat-public-transit',
    'e81a9206-0f6c-4719-8c5d-c4a8ec469a71': 'cat-shopping',
    '5e397b57-252c-4b49-bb95-e9e1734db4a4': 'cat-jewelry',
    '9419e816-1dc2-4084-94c8-52cc17b96c0f': 'cat-home-supplies',
    'f96d961a-5e1b-414d-9217-fed2d0d05c44': 'cat-insurance',
    '9183d65b-e325-41bd-94aa-e537eb43e2fd': 'cat-emi',
    '7c334c5c-a5e5-4330-b53f-999752de1691': 'cat-home-supplies',
    'a07289de-0c71-40bc-9472-242888531f9f': 'cat-movies',
    '1a6a2221-2589-40b8-9253-f4027faa7129': 'cat-gaming',
    'cat-movies-events': 'cat-movies',
    'eaa8a71e-ca6a-4a44-b331-7693b563cc52': 'cat-books',
    'cat-travel': 'cat-vacations',
    'b376d6a2-0296-4dbd-9483-64e76dcb82ad': 'cat-taxi-rides',
    '8136d975-4b1f-46d3-9235-ca7b1372c501': 'cat-flights',
    '88c2d1b6-77b9-4c16-917b-6fb2bd8c1f8c': 'cat-visas',
    'cat-courses': 'cat-education',
    '082152b2-121e-4c64-a576-eb710799196a': 'cat-education',
    '54a2747f-4f7f-4b6f-92da-795eda4ec628': 'cat-education',
    'cat-work-business': 'cat-professional-services',
    'cat-software': 'cat-subscriptions',
    'cat-business-travel': 'cat-flights',
    'cat-loan-interest': 'cat-emi',
  };

  int updatedTx = 0;
  final txs = payload['transactions'] as List<dynamic>;
  for (var tx in txs) {
    if (tx['categoryId'] != null && catMap.containsKey(tx['categoryId'])) {
      tx['categoryId'] = catMap[tx['categoryId']];
      updatedTx++;
    }
  }

  int updatedRules = 0;
  final prefs = payload['preferences'] as Map<String, dynamic>;
  final rules = (prefs['futureGenerationRules'] as List<dynamic>?) ?? [];
  for (var r in rules) {
    if (r['categoryId'] != null && catMap.containsKey(r['categoryId'])) {
      r['categoryId'] = catMap[r['categoryId']];
      updatedRules++;
    }
  }
  
  int updatedBudgets = 0;
  final budgets = (payload['budgets'] as List<dynamic>?) ?? [];
  for (var b in budgets) {
     if (b['categoryIds'] != null) {
         List<dynamic> cids = b['categoryIds'];
         for (int i=0; i<cids.length; i++) {
             if (catMap.containsKey(cids[i])) {
                 cids[i] = catMap[cids[i]];
                 updatedBudgets++;
             }
         }
     }
  }

  // Replace all categories with lifeCategoryTaxonomy
  final newCategories = lifeCategoryTaxonomy().map((c) => c.toJson()).toList();
  payload['categories'] = newCategories;

  print('Updated $updatedTx transactions');
  print('Updated $updatedRules rules');
  print('Updated $updatedBudgets budget category refs');
  print('Replaced all categories with ${newCategories.length} new categories.');

  // Re-encode payload
  final newPayloadStr = jsonEncode(payload);
  final newChecksum = fnv1a32Hex(newPayloadStr);

  decoded['payload'] = newPayloadStr;
  decoded['checksum'] = newChecksum;

  final fixedFile = File('../../../1wallet_backup_fixed.onewallet');
  fixedFile.writeAsStringSync(jsonEncode(decoded));
  print('Fixed backup saved to 1wallet_backup_fixed.onewallet');
}
