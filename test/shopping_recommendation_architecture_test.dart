import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('engine depends only on upstream Results and recommendation domain', () {
    final engine = File(
      'lib/shopping_recommendation/engine/shopping_recommendation_engine.dart',
    ).readAsStringSync();
    final input = File(
      'lib/shopping_recommendation/domain/shopping_recommendation_input.dart',
    ).readAsStringSync();

    for (final forbidden in [
      'package:flutter',
      'Repository',
      'InventoryService',
      'PurchaseService',
      'SharedPreferences',
      'InventoryHealthEngine',
      'ConsumptionEngine',
      'LowStockEngine',
      'DateTime.now',
      'dailyConsumption =',
      'projectedQuantity =',
    ]) {
      expect(engine, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(input, contains('InventoryHealthResult healthResult'));
    expect(input, contains('ConsumptionResult consumptionResult'));
    expect(input, contains('LowStockResult lowStockResult'));
    expect(RegExp(r'^  final .*Result ', multiLine: true).allMatches(input),
        hasLength(3));
  });

  test('feature is derived, read-only, and has no reverse dependencies', () {
    final featureSource = Directory('lib/shopping_recommendation')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    for (final forbidden in [
      'SharedPreferences',
      'InventoryRepository',
      'PurchaseRepository',
      '.save(',
      '.delete(',
      '.update(',
      'addShopping',
      'Notification',
    ]) {
      expect(featureSource, isNot(contains(forbidden)), reason: forbidden);
    }
    for (final directory in [
      'lib/inventory_health',
      'lib/consumption',
      'lib/low_stock/domain',
      'lib/low_stock/engine',
    ]) {
      final upstream = Directory(directory)
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .map((file) => file.readAsStringSync())
          .join('\n');
      expect(upstream, isNot(contains('shopping_recommendation')));
    }
  });
}
