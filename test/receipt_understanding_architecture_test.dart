import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine depends only on OCR and Receipt Understanding domain models',
      () {
    final engineFiles = Directory('lib/receipt_understanding/engine')
        .listSync()
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join('\n');
    for (final forbidden in [
      'package:flutter',
      'google_mlkit',
      'Repository',
      'SharedPreferences',
      'InventoryService',
      'PurchaseService',
      'ProductMatching',
      'ReceiptValidation',
      'DateTime.now',
      'Random(',
      'Uuid',
    ]) {
      expect(engineFiles, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(engineFiles, contains('ReceiptOcrBlock'));
    expect(engineFiles, isNot(contains('.lines')));
    expect(engineFiles, isNot(contains('.words')));
  });

  test('structural dictionary is isolated and retailer agnostic', () {
    final dictionary = File(
      'lib/receipt_understanding/engine/structural_receipt_dictionary.dart',
    ).readAsStringSync();
    final rules = File(
      'lib/receipt_understanding/engine/receipt_classification_rules.dart',
    ).readAsStringSync();
    expect(rules, contains('StructuralReceiptDictionary'));
    for (final forbidden in [
      'Carrefour',
      'Walmart',
      'Panda',
      'Danube',
      'milk',
      'rice',
      'bread',
    ]) {
      expect(
          dictionary.toLowerCase(), isNot(contains(forbidden.toLowerCase())));
    }
  });

  test('feature is read-only with no reverse or business dependencies', () {
    final feature = Directory('lib/receipt_understanding')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    for (final forbidden in [
      '.save(',
      '.delete(',
      '.update(',
      'ShoppingList',
      'PurchaseRepository',
      'InventoryRepository',
      'ProductRepository',
      'StoreRepository',
      'AIService',
      'Cloud',
    ]) {
      expect(feature, isNot(contains(forbidden)), reason: forbidden);
    }
    final ocrDomain = Directory('lib/receipt_ocr/domain')
        .listSync()
        .whereType<File>()
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(ocrDomain, isNot(contains('receipt_understanding')));
  });
}
